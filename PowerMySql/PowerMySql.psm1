$Missing = $False

try {
    if (-not [MySql.Data.MySqlClient.MySqlConnection])
    {
        $Missing = $true
    }
}
catch {
    $Missing = $True
}

if ($Missing)
{
    add-type -Path 'C:\Program Files (x86)\MySQL\MYSQL Connector NET 8.0.29\Assemblies\v4.5.2\MySql.Data.dll'
}

Function Get-MySqlConnection
{
    param 
    (
        $Creds,
        $ComputerName,
        $DBName
    )
    if (-not $Creds)
    {
        $Creds = Get-Credential
    }
    return [MySql.Data.MySqlClient.MySqlConnection]@{ConnectionString="server=$ComputerName;user=$($Creds.UserName);pwd=$($Creds.GetNetworkCredential().Password);database=$DBName"}
}

Function Get-MySqlTables
{
    param
    (
        $Connection,
        $Database
    )

    $Command = "show tables in $Database"
    
    $Reader = (Get-MySqlCommand $Connection $Command).ExecuteReader()

    $Return = @()

    while ($Reader.read())
    {
        $Return += New-Object PSObject -Property @{
            "Name" = $Reader[0]
            #"Columns" = (Get-MySqlTableColumns $Connection $Database $Reader[0])
        }
    }

    $Reader.Close()

    foreach ($Table in $Return)
    {
        $Table | add-member -type NoteProperty -name Columns -value (Get-MySqlTableColumns $Connection $Database $Table.Name) -force
    }

    return $Return
}

Function Get-MySqlTableColumns
{
    param
    (
        $Connection,
        $Database,
        $TableName
    )
    
    $Reader = (Get-MySqlCommand $Connection "show columns in $Database.$TableName").ExecuteReader()

    $Return = @()

    if ($Reader)
    {
        while ($Reader.read())
        {
            $Return += New-Object PSObject -Property @{
                "Name" = $Reader[0]
                "Type" = $Reader[1]
                "Null" = $Reader[2]
                "Key" = $Reader[3]
                "Default" = $Reader[4]
                "Extra" = $Reader[5]
            }
        }

        $Reader.Close()
    }

    return $Return
}

Function Get-MySqlCommand
{
    param
    (
        $Connection,
        $Command
    )

    $SQLCommand = New-Object MySql.Data.MySqlClient.MySqlCommand
    $SQLCommand.Connection = $Connection
    Write-Debug "Running Command - $Command"
    $SQLCommand.CommandText = $Command

    return $SQLCommand
}

Function Get-MySqlTableDump
{
    param
    (
        $Connection,
        $Database,
        $TableName
    )
    $Columns = Get-MySqlTableColumns $Connection $Database $TableName

    $Return = Get-MySqlRows $Connection $Database $TableName $null $Columns

    return $Return
}

Function Get-MySqlRows
{
    param
    (
        $Connection,
        $Database,
        $TableName,
        $Conditions,
        $Columns
    )

    if (-not $Columns)
    {
        $Columns = Get-MySqlTableColumns $Connection $Database $TableName
    }

    $tofs = $ofs
    $ofs = ","

    $Command = "select $($Columns.Name) from $Database.$TableName"
    #$Command 
    if ($Conditions)
    {
        $Command += " $Conditions"
    }

    return (Invoke-MySqlQuery $Connection $Command $Columns)
}

Function Invoke-MySqlQuery
{
    param
    (
        $Connection,
        $Command,
        $Columns
    )
   
    #Write-Verbose "$Command"

    $Reader = (Get-MySqlCommand $Connection $Command).ExecuteReader()

    $Return = @()

    if ($Reader)
    {
        while ($Reader.read())
        {
            $Row = new-object PSObject
            $ColNo = 0
            foreach ($Column in $Columns)
            {
                $Row | add-member -type NoteProperty -name $Column.Name -Value $Reader[$ColNo] -force
                $ColNo++
            }

            $Return += $Row
        }

        $Reader.Close()       
    }

    return $Return
}

Function Invoke-MySqlInsert
{
    param
    (
        $Connection,
        $Database,
        $Table,
        $ColumnNames,
        $ColumnData
    )
    $tofs = $ofs

    $ofs = ","

    $Command = "INSERT INTO $Database.$Table ($ColumnNames) VALUES "
    $ofs = "','"

    $Command += "('$ColumnData')"
    $Command = $Command -replace "'NULL'","NULL"
    $Command = $Command -replace "'(0x[^']*)'",'$1'
    
    $ofs = $tofs
    return (Invoke-MySqlNonQuery $Connection $Command)
}

Function Invoke-MySqlNonQuery
{
    param
    (
        $Connection,
        $Command
    )

    return (Get-MySqlCommand $Connection $Command).ExecuteNonQuery()
}