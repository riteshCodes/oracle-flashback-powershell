<#
.SYNOPSIS
    .
.DESCRIPTION
    Helper script to check and activate flashback, create a restore point and rollback/restore to the available restore point in DB
.NOTES
    Author: Ritesh Shrestha
    Date:   December, 2022    
#>

# credential to connect to the database
Param (
    [String][Parameter(Mandatory,HelpMessage='Specify username, Flag: -user')]$user,								# Username to login at DB
	[String][Parameter(Mandatory,HelpMessage='Specify password, Flag: -password')]$password							# Password to login at DB
)


# Default parameters
# $oracleRecoveryFileDestination = "C:\oracle\flashback"
# $defaultRestorePointName = "AUTOTEST_RESTOREPOINT";


# Wrapper funtion to run powershell command (iex: invoke expression)
function RunShellCommand {
    param (
        [Parameter()]
         $Cmd
    )
    $output = iex $Cmd
    Write-Output "iex `"$($Cmd)`""
    return $output
}


# Wrapper funtion to run sql queries
function RunSqlPlusCommand {
    param (
        [Parameter()]
         $Cmd
    )
    return  RunShellCommand -Cmd  "echo '$Cmd' | sqlplus $user/$password as SYSDBA"
}


# Wrapper funtion to run Oracle Recovery Manager (RMAN) commands for backup and recovery
function RunRmanCommand {
    param (
        [Parameter()]
         $Cmd
    )
    return RunShellCommand -Cmd  "echo '$Cmd' | rman TARGET $user/$password"
}



# Function to check if flashback feature is activated or deactivated
# Returns an array of available flashback points, ONLY if flashback feature is already activated AND restore points are present in DB
function checkFlashbackStatus {
  # Check if flashback is enabled
    Write-Host "Checking Flashback status"

    $flashbackCmd = 'select flashback_on from v$database;'

    $flashbackOutput = RunSqlPlusCommand -Cmd $flashbackCmd
    $flashbackValueLine = -1
    
    for ($i=0; $i-le $flashbackOutput.length-1; $i++)
    {
        if ($flashbackOutput[$i] -eq "------------------") # filter the command output to get the only flashback status value (string)
        {
            $flashbackValueLine = $i + 1
            break;
        }
    }

    if ($flashbackValueLine -eq -1) 
    {
        throw "Output of $($flashbackCmd) invalid. Output: $($flashbackOutput)" # throw error of command (if present)
    }
            
    if ($flashbackOutput[$flashbackValueLine] -ne "NO") # case: if flashback is already activated
    {
        Write-Host "Flashback Status: Enabled"

        $availableRestorePoints = RunSqlPlusCommand -Cmd 'select name from v$restore_point;' # command to fetch available restore points, which are present
                
        for ($i=0; $i-lt $availableRestorePoints.length-2; $i++) {
            if ($flashbackOutput[$i] -eq "------------------")
            {
                $pointLine = $i + 1
                for ($j=$pointLine; $j-lt $availableRestorePoints.length-2; $j++) 
                {
                    $availableRestorePoints[$j] # Output: restore point name
                }
                break;
            }
        }
    }

    else # case: if flashback is disabled
    {
        Write-Host "Flashback is not enabled."
        return
    }
}



# Function to enable flashback feature
# @flag -recoveryFileDestination, recovery file destination directory path, which stores all the log files needed for the recovery, example: enableFlashback -recoveryFileDestination "C:\oracle\flashback"
# PRECONDITION: Flashback feature is not enabled from function: checkFlashbackStatus
function enableFlashback {
    Param (
    [String][Parameter(Mandatory,HelpMessage='Specify the recoveryFileDestination, flag: -recoveryFileDestination')]$recoveryFileDestination)
    Write-Host "Flashback is not enabled. Starting to enable it."
    
    Write-Host "Create Oracle db_recovery_file_dest dir '$($recoveryFileDestination)'"
    RunShellCommand -Cmd "mkdir -p $($recoveryFileDestination)"
    
    Write-Host "Shutdown Database"
    RunRmanCommand -Cmd "SHUTDOWN IMMEDIATE"
    
    Write-Host "Mount Database"
    RunRmanCommand -Cmd "STARTUP MOUNT"
    
    # To enable flashback two parameters are needed: DB_RECOVERY_FILE_DEST (recovery file destination) and DB_RECOVERY_FILE_DEST_SIZE (recovery file maximum allocated size)
    Write-Host "Configure recovery settings"
    RunRmanCommand -Cmd "alter system set db_recovery_file_dest_size=20G;"
    RunRmanCommand -Cmd "alter system set db_recovery_file_dest=""$recoveryFileDestination"";"
    
    Write-Host "Place the database in ARCHIVELOG mode"
    RunRmanCommand -Cmd "alter database archivelog;"
    
    Write-Host "Enable Flashback mode"
    RunRmanCommand -Cmd "ALTER DATABASE FLASHBACK ON;" # command to enable flashback
    
    Write-Host "Start database"
    RunRmanCommand -Cmd "STARTUP"
    
    Write-Host "Flashback is enabled."

}



# Function to create a restore point
# @flag -restorePointName, specify the name for the restore point, example: createFlashbackPoint -restorePointName "RestorePointName"
function createFlashbackPoint {
    Param(
    [String][Parameter(Mandatory, HelpMessage='Specify the flashback restore point for database recovery, flag: -restorePointName')]$restorePointName)
    
    Write-Output "Create a restore point"
    RunRmanCommand -Cmd "CREATE RESTORE POINT $restorePointName;"
            
    Write-Output "Restore point: $restorePointName sucessfully created"
}



# Function to restore the database from given flashback point name
# @flag -restorePointName, specify the name for the restore point to recover from, example: restoreFromFlashback -restorePointName "RestorePointName"
function restoreFromFlashback {
    Param(
    [String][Parameter(Mandatory, HelpMessage='Specify the flashback restore point for database recovery, flag: -restorePointName')]$restorePointName)

    RunRmanCommand -Cmd "SHUTDOWN IMMEDIATE;"
    Write-Output "Oracle instance is shut down"
    
    RunRmanCommand -Cmd "STARTUP MOUNT;"
    Write-Output "Database mounted"

    RunRmanCommand -Cmd "FLASHBACK DATABASE TO RESTORE POINT $restorePointName;" # command to restore the database from the given restore point name
    Write-Output "Rollback to restore point"
                            
    RunRmanCommand -Cmd "ALTER DATABASE OPEN RESETLOGS;"
    Write-Output "Finished flashback"
 
}



# Function to drop/delete the restore point
# @flag -restorePointName, specify the restore point that needs to be deleted, example: dropRestorePoint -restorePointName "RestorePointName"
function dropRestorePoint {
    Param(
    [String][Parameter(Mandatory, HelpMessage='Specify the flashback restore point to delete, flag: -restorePointName')]$restorePointName)

    Write-Host "Delete restore point: $restorePointName"
    RunRmanCommand -Cmd "DROP RESTORE POINT $restorePointName;" # command to drop the given restore-point from the DB table

}

# Function to disable flashback feature, if activated
function disableFlashback {
    
    Write-Host "Disable Flashback mode"
    RunRmanCommand -Cmd "ALTER DATABASE FLASHBACK OFF;" # command to enable flashback
    
    Write-Host "Flashback is disabled."

}


<# -------------------------------------------------------------------------------------------------------------------------------------------- #>


<#
# Flashback function
function flashback {
    Param (
    [String][Parameter(Mandatory,HelpMessage='Function: createFlashbackPoint, enableFlashback, restoreDB')]$function)
    		
    switch ($function)
    {
        
        enableFlashback
        {
            # Check if flashback is enabled
            Write-Host "Checking Flashback status"

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
                Write-Host "Flashback already enabled"
            }
            else
            {
            # Enable Flashback feature
                Write-Host "Flashback is not enabled. Starting to enable it."

                Write-Host "Create Oracle db_recovery_file_dest dir '$($oracleRecoveryFileDestination)'"
                RunShellCommand -Cmd "mkdir -p $($oracleRecoveryFileDestination)"

                Write-Host "Shutdown Database"
                RunRmanCommand -Cmd "SHUTDOWN IMMEDIATE"

                Write-Host "Mount Database"
                RunRmanCommand -Cmd "STARTUP MOUNT"

                Write-Host "Configure recovery settings"
                RunRmanCommand -Cmd "alter system set db_recovery_file_dest_size=20G;"
                RunRmanCommand -Cmd "alter system set db_recovery_file_dest=""$oracleRecoveryFileDestination"";"

                Write-Host "Place the database in ARCHIVELOG mode"
                RunRmanCommand -Cmd "alter database archivelog;"

                Write-Host "Enable Flashback mode"
                RunRmanCommand -Cmd "ALTER DATABASE FLASHBACK ON;"

                Write-Host "Start database"
                RunRmanCommand -Cmd "STARTUP"

                Write-Host "Flashback is enabled."

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
#>