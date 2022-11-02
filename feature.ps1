<#
.SYNOPSIS
    .
.DESCRIPTION
    Helper Tool to check and activate flashback, create a restore point and rollback to the restore point in DB
.NOTES
    Author: Ritesh Shrestha
    Date:   November, 2022    
#>


# Default parameters
$oracleRecoveryFileDestination = "C:\oracle\recoveryFileDestination"
$defaultRestorePointName = "DEFAULT_RESTOREPOINT_NAME";

# Wrapper funtions
function RunShellCommand {
    param (
        [Parameter()]
         $Cmd
    )
    $output = iex $Cmd
    Write-Output "iex `"$($Cmd)`""
    return $output
}

function RunSqlPlusCommand {
    param (
        [Parameter()]
         $Cmd
    )
    return  RunShellCommand -Cmd  "echo '$Cmd' | sqlplus SYS/<password> as SYSDBA"
}

function RunRmanCommand {
    param (
        [Parameter()]
         $Cmd
    )
    return RunShellCommand -Cmd  "echo '$Cmd' | rman TARGET SYS/<password>"
}

# Flashback function
function flashback {
    Param (
    [String][Parameter(Mandatory,HelpMessage='Function: createFlashbackPoint, enableFlashback, restoreDB')]$function)
    		
    switch ($function)
    {
        
        enableFlashback
        {
            # Check if flashback is enabled
            Write-Output "Checking Flashback status"

            $flashbackCmd = 'select flashback_on from v$database;'

            $flashbackOutput = RunSqlPlusCommand -Cmd $flashbackCmd
            $flashbackValueLine = -1
            for ($i=0; $i-le $flashbackOutput.length-1; $i++)
            {
                if ($flashbackOutput[$i] -eq "------------------")
                {
                    $flashbackValueLine = $i + 1
                    break;
                }
            }

            if ($flashbackValueLine -eq -1)
            {
                throw "Output of $($flashbackCmd) invalid. Output: $($flashbackOutput)" 
            }

            if ($flashbackOutput[$flashbackValueLine] -ne "NO")
            {
                Write-Output "Flashback already enabled"
            }
            else
            {
            # Enable Flashback feature
                Write-Output "Flashback is not enabled. Starting to enable it."

                Write-Output "Create Oracle db_recovery_file_dest dir '$($oracleRecoveryFileDestination)'"
                RunShellCommand -Cmd "mkdir -p $($oracleRecoveryFileDestination)"

                Write-Output "Shutdown Database"
                RunRmanCommand -Cmd "SHUTDOWN IMMEDIATE"

                Write-Output "Mount Database"
                RunRmanCommand -Cmd "STARTUP MOUNT"

                Write-Output "Configure recovery settings"
                RunRmanCommand -Cmd "alter system set db_recovery_file_dest_size=20G;"
                RunRmanCommand -Cmd "alter system set db_recovery_file_dest=""$oracleRecoveryFileDestination"";"

                Write-Output "Place the database in ARCHIVELOG mode"
                RunRmanCommand -Cmd "alter database archivelog;"

                Write-Output "Enable Flashback mode"
                RunRmanCommand -Cmd "ALTER DATABASE FLASHBACK ON;"

                Write-Output "Start database"
                RunRmanCommand -Cmd "STARTUP"

                Write-Output "Flashback is enabled."

            }
            break;
        }




        createFlashbackPoint { 
            # Create a restore point
            Write-Output "Create a restore point"
            RunRmanCommand -Cmd "CREATE RESTORE POINT $defaultRestorePointName;"
            break;
        }



        
        restoreDB {
            # Flashback to default restore point
            RunRmanCommand -Cmd "SHUTDOWN IMMEDIATE;"
            Write-Output "Oracle instance is shut down"

            RunRmanCommand -Cmd "STARTUP MOUNT;"
            Write-Output "Database mounted"

            RunRmanCommand -Cmd "FLASHBACK DATABASE TO RESTORE POINT $defaultRestorePointName;"
            Write-Output "Rollback to restore point"
                            
            RunRmanCommand -Cmd "ALTER DATABASE OPEN RESETLOGS;"
            Write-Output "Finished flashback"
            
            break;
        }
       
   }
          
}