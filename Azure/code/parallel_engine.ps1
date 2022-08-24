function Invoke-Parallel {
    [cmdletbinding(DefaultParameterSetName='ScriptBlock')]
        Param (   
            [Parameter(Mandatory=$false,position=0,ParameterSetName='ScriptBlock')]
                [System.Management.Automation.ScriptBlock]$ScriptBlock,
    
            [Parameter(Mandatory=$false,ParameterSetName='ScriptFile')]
            [ValidateScript({test-path $_ -pathtype leaf})]
                $ScriptFile,
    
            [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
            [Alias('CN','__Server','IPAddress','Server','ComputerName')]    
                [PSObject]$InputObject,
    
                [PSObject]$Parameter,
    
                [switch]$ImportVariables,
    
                [switch]$ImportModules,
    
                [int]$Throttle = 20,
    
                [int]$SleepTimer = 200,
    
                [int]$RunspaceTimeout = 0,
    
                [switch]$NoCloseOnTimeout = $false,
    
                [int]$MaxQueue,
    
            [validatescript({Test-Path (Split-Path $_ -parent)})]
                [string]$LogFile = "C:\temp\log.log",
    
                [switch] $Quiet = $false
        )
        
        Begin {
                    
            #No max queue specified?  Estimate one.
            #We use the script scope to resolve an odd PowerShell 2 issue where MaxQueue isn't seen later in the function
            if( -not $PSBoundParameters.ContainsKey('MaxQueue') )
            {
                if($RunspaceTimeout -ne 0){ $script:MaxQueue = $Throttle }
                else{ $script:MaxQueue = $Throttle * 3 }
            }
            else
            {
                $script:MaxQueue = $MaxQueue
            }
    
            Write-Verbose "Throttle: '$throttle' SleepTimer '$sleepTimer' runSpaceTimeout '$runspaceTimeout' maxQueue '$maxQueue' logFile '$logFile'"
    
            #If they want to import variables or modules, create a clean runspace, get loaded items, use those to exclude items
            if ($ImportVariables -or $ImportModules)
            {
                $StandardUserEnv = [powershell]::Create().addscript({
    
                    #Get modules and snapins in this clean runspace
                    $Modules = Get-Module | Select -ExpandProperty Name
                    $Snapins = Get-PSSnapin | Select -ExpandProperty Name
    
                    #Get variables in this clean runspace
                    #Called last to get vars like $? into session
                    $Variables = Get-Variable | Select -ExpandProperty Name
                    
                    #Return a hashtable where we can access each.
                    @{
                        Variables = $Variables
                        Modules = $Modules
                        Snapins = $Snapins
                    }
                }).invoke()[0]
                
                if ($ImportVariables) {
                    #Exclude common parameters, bound parameters, and automatic variables
                    Function _temp {[cmdletbinding()] param() }
                    $VariablesToExclude = @( (Get-Command _temp | Select -ExpandProperty parameters).Keys + $PSBoundParameters.Keys + $StandardUserEnv.Variables )
                    Write-Verbose "Excluding variables $( ($VariablesToExclude | sort ) -join ", ")"
    
                    # we don't use 'Get-Variable -Exclude', because it uses regexps. 
                    # One of the veriables that we pass is '$?'. 
                    # There could be other variables with such problems.
                    # Scope 2 required if we move to a real module
                    $UserVariables = @( Get-Variable | Where { -not ($VariablesToExclude -contains $_.Name) } ) 
                    Write-Verbose "Found variables to import: $( ($UserVariables | Select -expandproperty Name | Sort ) -join ", " | Out-String).`n"
    
                }
    
                if ($ImportModules) 
                {
                    $UserModules = @( Get-Module | Where {$StandardUserEnv.Modules -notcontains $_.Name -and (Test-Path $_.Path -ErrorAction SilentlyContinue)} | Select -ExpandProperty Path )
                    $UserSnapins = @( Get-PSSnapin | Select -ExpandProperty Name | Where {$StandardUserEnv.Snapins -notcontains $_ } ) 
                }
            }
    
            #region functions
                
                Function Get-RunspaceData {
                    [cmdletbinding()]
                    param( [switch]$Wait )
    
                    #loop through runspaces
                    #if $wait is specified, keep looping until all complete
                    Do {
    
                        #set more to false for tracking completion
                        $more = $false
    
                        #Progress bar if we have inputobject count (bound parameter)
                        if (-not $Quiet) {
                            Write-Progress  -Activity "Running Query" -Status "Starting threads"`
                                -CurrentOperation "$startedCount threads defined - $totalCount input objects - $script:completedCount input objects processed"`
                                -PercentComplete $( Try { $script:completedCount / $totalCount * 100 } Catch {0} )
                        }
    
                        #run through each runspace.           
                        Foreach($runspace in $runspaces) {
                        
                            #get the duration - inaccurate
                            $currentdate = Get-Date
                            $runtime = $currentdate - $runspace.startTime
                            $runMin = [math]::Round( $runtime.totalminutes ,2 )
    
                            #set up log object
                            $log = "" | select Date, Action, Runtime, Status, Details
                            $log.Action = "Removing:'$($runspace.object)'"
                            $log.Date = $currentdate
                            $log.Runtime = "$runMin minutes"
    
                            #If runspace completed, end invoke, dispose, recycle, counter++
                            If ($runspace.Runspace.isCompleted) {
                                
                                $script:completedCount++
                            
                                #check if there were errors
                                if($runspace.powershell.Streams.Error.Count -gt 0) {
                                    
                                    #set the logging info and move the file to completed
                                    $log.status = "CompletedWithErrors"
                                    Write-Verbose ($log | ConvertTo-Csv -Delimiter ";" -NoTypeInformation)[1]
                                    foreach($ErrorRecord in $runspace.powershell.Streams.Error) {
                                        Write-Error -ErrorRecord $ErrorRecord
                                    }
                                }
                                else {
                                    
                                    #add logging details and cleanup
                                    $log.status = "Completed"
                                    Write-Verbose ($log | ConvertTo-Csv -Delimiter ";" -NoTypeInformation)[1]
                                }
    
                                #everything is logged, clean up the runspace
                                $runspace.powershell.EndInvoke($runspace.Runspace)
                                $runspace.powershell.dispose()
                                $runspace.Runspace = $null
                                $runspace.powershell = $null
    
                            }
    
                            #If runtime exceeds max, dispose the runspace
                            ElseIf ( $runspaceTimeout -ne 0 -and $runtime.totalseconds -gt $runspaceTimeout) {
                                
                                $script:completedCount++
                                $timedOutTasks = $true
                                
                                #add logging details and cleanup
                                $log.status = "TimedOut"
                                Write-Verbose ($log | ConvertTo-Csv -Delimiter ";" -NoTypeInformation)[1]
                                Write-Error "Runspace timed out at $($runtime.totalseconds) seconds for the object:`n$($runspace.object | out-string)"
    
                                #Depending on how it hangs, we could still get stuck here as dispose calls a synchronous method on the powershell instance
                                if (!$noCloseOnTimeout) { $runspace.powershell.dispose() }
                                $runspace.Runspace = $null
                                $runspace.powershell = $null
                                $completedCount++
    
                            }
                       
                            #If runspace isn't null set more to true  
                            ElseIf ($runspace.Runspace -ne $null ) {
                                $log = $null
                                $more = $true
                            }
    
                            #log the results if a log file was indicated
                            if($logFile -and $log){
                                ($log | ConvertTo-Csv -Delimiter ";" -NoTypeInformation)[1] | out-file $LogFile -append
                            }
                        }
    
                        #Clean out unused runspace jobs
                        $temphash = $runspaces.clone()
                        $temphash | Where { $_.runspace -eq $Null } | ForEach {
                            $Runspaces.remove($_)
                        }
    
                        #sleep for a bit if we will loop again
                        if($PSBoundParameters['Wait']){ Start-Sleep -milliseconds $SleepTimer }
    
                    #Loop again only if -wait parameter and there are more runspaces to process
                    } while ($more -and $PSBoundParameters['Wait'])
                    
                #End of runspace function
                }
    
            #endregion functions
            
            #region Init
    
                if($PSCmdlet.ParameterSetName -eq 'ScriptFile')
                {
                    $ScriptBlock = [scriptblock]::Create( $(Get-Content $ScriptFile | out-string) )
                }
                elseif($PSCmdlet.ParameterSetName -eq 'ScriptBlock')
                {
                    #Start building parameter names for the param block
                    [string[]]$ParamsToAdd = '$_'
                    if( $PSBoundParameters.ContainsKey('Parameter') )
                    {
                        $ParamsToAdd += '$Parameter'
                    }
    
                    $UsingVariableData = $Null
                    
    
                    # This code enables $Using support through the AST.
                    # This is entirely from  Boe Prox, and his https://github.com/proxb/PoshRSJob module; all credit to Boe!
                    
                    if($PSVersionTable.PSVersion.Major -gt 2)
                    {
                        #Extract using references
                        $UsingVariables = $ScriptBlock.ast.FindAll({$args[0] -is [System.Management.Automation.Language.UsingExpressionAst]},$True)    
    
                        If ($UsingVariables)
                        {
                            $List = New-Object 'System.Collections.Generic.List`1[System.Management.Automation.Language.VariableExpressionAst]'
                            ForEach ($Ast in $UsingVariables)
                            {
                                [void]$list.Add($Ast.SubExpression)
                            }
    
                            $UsingVar = $UsingVariables | Group SubExpression | ForEach {$_.Group | Select -First 1}
            
                            #Extract the name, value, and create replacements for each
                            $UsingVariableData = ForEach ($Var in $UsingVar) {
                                Try
                                {
                                    $Value = Get-Variable -Name $Var.SubExpression.VariablePath.UserPath -ErrorAction Stop
                                    [pscustomobject]@{
                                        Name = $Var.SubExpression.Extent.Text
                                        Value = $Value.Value
                                        NewName = ('$__using_{0}' -f $Var.SubExpression.VariablePath.UserPath)
                                        NewVarName = ('__using_{0}' -f $Var.SubExpression.VariablePath.UserPath)
                                    }
                                }
                                Catch
                                {
                                    Write-Error "$($Var.SubExpression.Extent.Text) is not a valid Using: variable!"
                                }
                            }
                            $ParamsToAdd += $UsingVariableData | Select -ExpandProperty NewName -Unique
    
                            $NewParams = $UsingVariableData.NewName -join ', '
                            $Tuple = [Tuple]::Create($list, $NewParams)
                            $bindingFlags = [Reflection.BindingFlags]"Default,NonPublic,Instance"
                            $GetWithInputHandlingForInvokeCommandImpl = ($ScriptBlock.ast.gettype().GetMethod('GetWithInputHandlingForInvokeCommandImpl',$bindingFlags))
            
                            $StringScriptBlock = $GetWithInputHandlingForInvokeCommandImpl.Invoke($ScriptBlock.ast,@($Tuple))
    
                            $ScriptBlock = [scriptblock]::Create($StringScriptBlock)
    
                            Write-Verbose $StringScriptBlock
                        }
                    }
                    
                    $ScriptBlock = $ExecutionContext.InvokeCommand.NewScriptBlock("param($($ParamsToAdd -Join ", "))`r`n" + $Scriptblock.ToString())
                }
                else
                {
                    Throw "Must provide ScriptBlock or ScriptFile"; Break
                }
    
                Write-Debug "`$ScriptBlock: $($ScriptBlock | Out-String)"
                Write-Verbose "Creating runspace pool and session states"
    
                #If specified, add variables and modules/snapins to session state
                $sessionstate = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
                if ($ImportVariables)
                {
                    if($UserVariables.count -gt 0)
                    {
                        foreach($Variable in $UserVariables)
                        {
                            $sessionstate.Variables.Add( (New-Object -TypeName System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList $Variable.Name, $Variable.Value, $null) )
                        }
                    }
                }
                if ($ImportModules)
                {
                    if($UserModules.count -gt 0)
                    {
                        foreach($ModulePath in $UserModules)
                        {
                            $sessionstate.ImportPSModule($ModulePath)
                        }
                    }
                    if($UserSnapins.count -gt 0)
                    {
                        foreach($PSSnapin in $UserSnapins)
                        {
                            [void]$sessionstate.ImportPSSnapIn($PSSnapin, [ref]$null)
                        }
                    }
                }
    
                #Create runspace pool
                $runspacepool = [runspacefactory]::CreateRunspacePool(1, $Throttle, $sessionstate, $Host)
                $runspacepool.Open() 
    
                Write-Verbose "Creating empty collection to hold runspace jobs"
                $Script:runspaces = New-Object System.Collections.ArrayList        
            
                #If inputObject is bound get a total count and set bound to true
                $bound = $PSBoundParameters.keys -contains "InputObject"
                if(-not $bound)
                {
                    [System.Collections.ArrayList]$allObjects = @()
                }
    
                #Set up log file if specified
                if( $LogFile ){
                    New-Item -ItemType file -path $logFile -force | Out-Null
                    ("" | Select Date, Action, Runtime, Status, Details | ConvertTo-Csv -NoTypeInformation -Delimiter ";")[0] | Out-File $LogFile
                }
    
                #write initial log entry
                $log = "" | Select Date, Action, Runtime, Status, Details
                    $log.Date = Get-Date
                    $log.Action = "Batch processing started"
                    $log.Runtime = $null
                    $log.Status = "Started"
                    $log.Details = $null
                    if($logFile) {
                        ($log | convertto-csv -Delimiter ";" -NoTypeInformation)[1] | Out-File $LogFile -Append
                    }
    
                $timedOutTasks = $false
    
            #endregion INIT
        }
    
        Process {
    
            #add piped objects to all objects or set all objects to bound input object parameter
            if($bound)
            {
                $allObjects = $InputObject
            }
            Else
            {
                [void]$allObjects.add( $InputObject )
            }
        }
    
        End {
            
            #Use Try/Finally to catch Ctrl+C and clean up.
            Try
            {
                #counts for progress
                $totalCount = $allObjects.count
                $script:completedCount = 0
                $startedCount = 0
    
                foreach($object in $allObjects){
            
                    #region add scripts to runspace pool
                        
                        #Create the powershell instance, set verbose if needed, supply the scriptblock and parameters
                        $powershell = [powershell]::Create()
                        
                        if ($VerbosePreference -eq 'Continue')
                        {
                            [void]$PowerShell.AddScript({$VerbosePreference = 'Continue'})
                        }
    
                        [void]$PowerShell.AddScript($ScriptBlock).AddArgument($object)
    
                        if ($parameter)
                        {
                            [void]$PowerShell.AddArgument($parameter)
                        }
    
                        # $Using support from Boe Prox
                        if ($UsingVariableData)
                        {
                            Foreach($UsingVariable in $UsingVariableData) {
                                Write-Verbose "Adding $($UsingVariable.Name) with value: $($UsingVariable.Value)"
                                [void]$PowerShell.AddArgument($UsingVariable.Value)
                            }
                        }
    
                        #Add the runspace into the powershell instance
                        $powershell.RunspacePool = $runspacepool
        
                        #Create a temporary collection for each runspace
                        $temp = "" | Select-Object PowerShell, StartTime, object, Runspace
                        $temp.PowerShell = $powershell
                        $temp.StartTime = Get-Date
                        $temp.object = $object
        
                        #Save the handle output when calling BeginInvoke() that will be used later to end the runspace
                        $temp.Runspace = $powershell.BeginInvoke()
                        $startedCount++
    
                        #Add the temp tracking info to $runspaces collection
                        Write-Verbose ( "Adding {0} to collection at {1}" -f $temp.object, $temp.starttime.tostring() )
                        $runspaces.Add($temp) | Out-Null
                
                        #loop through existing runspaces one time
                        Get-RunspaceData
    
                        #If we have more running than max queue (used to control timeout accuracy)
                        #Script scope resolves odd PowerShell 2 issue
                        $firstRun = $true
                        while ($runspaces.count -ge $Script:MaxQueue) {
    
                            #give verbose output
                            if($firstRun){
                                Write-Verbose "$($runspaces.count) items running - exceeded $Script:MaxQueue limit."
                            }
                            $firstRun = $false
                        
                            #run get-runspace data and sleep for a short while
                            Get-RunspaceData
                            Start-Sleep -Milliseconds $sleepTimer
                        
                        }
    
                    #endregion add scripts to runspace pool
                }
                         
                Write-Verbose ( "Finish processing the remaining runspace jobs: {0}" -f ( @($runspaces | Where {$_.Runspace -ne $Null}).Count) )
                Get-RunspaceData -wait
    
                if (-not $quiet) {
                    Write-Progress -Activity "Running Query" -Status "Starting threads" -Completed
                }
            }
            Finally
            {
                #Close the runspace pool, unless we specified no close on timeout and something timed out
                if ( ($timedOutTasks -eq $false) -or ( ($timedOutTasks -eq $true) -and ($noCloseOnTimeout -eq $false) ) ) {
                    Write-Verbose "Closing the runspace pool"
                    $runspacepool.close()
                }
    
                #collect garbage
                [gc]::Collect()
            }       
        }
    }