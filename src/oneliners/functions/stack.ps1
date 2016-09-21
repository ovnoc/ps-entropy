﻿
function add-stackitem {
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)] $what, 
        $stackname = "default", 
        [switch][bool] $get, 
        [Alias("est")] $estimatedTime,
        [alias("c")]
        [switch][bool] $asChild,
        [alias("i")]
        [switch][bool]$interruption,
        $level = 0) 

    $stack = import-cache -container "stack.$stackname" -dir (get-syncdir)
    
    if ($stack -eq $null) { $stack = @(); $no = 1 }
    else { $stack = @($stack); $no =  (($stack | measure -Property "no" -Maximum).maximum) + 1 }

    if ($estimatedTime -ne $null) {
       if ($estimatedTime -match "([0-9]+)p") {
           $estimatedTime = [timespan]::FromMinutes([int]::Parse($matches[1]) * 30)
       }   
       elseif ($estimatedTime -match "([0-9]+)(m|min)") {
           $estimatedTime = [timespan]::FromMinutes([int]::Parse($matches[1]))
       }
       else {
           $estimatedTime = [timespan]::Parse($estimatedTime)
       }
    } else {
        $estimatedTime = [timespan]::FromMinutes(5)
    }

    $parent = $null
    if ($asChild) {
        $parent = peek -stackname $stackname
    }

    if ($parent -ne $null) {
        $plev = $parent.level 
        if ($plev -eq $null) { $plev = 0 }
        $level = $plev + 1
    }

    if ($interruption) {
        $level = 0
        $what = "▼ " + $what
    }

    if ($level -gt 0 -and $what.gettype() -eq [string]) {
        $what = ('┗' + [string]$what)
        $what = $what.Padleft($what.length + $level)
    }

    $props = [ordered]@{
        no = $no
        value = $what
        ts = get-date -Format "yyyy-MM-dd HH:mm:ss"
        est = $estimatedTime.ToString()
        level = $level
    }
    $item = new-object -type pscustomobject -Property $props
    $stack += @($item)
    export-cache -data $stack -container "stack.$stackname"  -dir (get-syncdir)
    if ($get) {
        return peek -stackname $stackname
    } else {
        invoke-stackcmd -cmd show -stackname $stackname
    }
}
new-alias push add-stackitem

function remove-stackitem {
    param($stackname = "default",[switch][bool]$get) 
    
    $stack = import-cache -container "stack.$stackname" -dir (get-syncdir)
    if ($stack -eq $null -or $stack.length -eq 0) { return $null }
    else { $stack = @($stack) }
    $item = $stack[$stack.length-1]
    $stack = $stack | select -First ($stack.Length-1)
    if ($stack -eq $null) {
        remove-stack -stackname "$stackname" -Confirm:$false
    } else {
        export-cache -data $stack -container "stack.$stackname" -dir (get-syncdir)
    }

    if ($get) {
        Write-Output $item
    } else {
        Write-host (get-stack $stackname | format-table | out-string)
    }

    $started = [datetime]::parse($item.ts)
    $now = get-date
    $elapsed = $now - $started
    write-host ""
    write-host "task $($item.value) took: $elapsed (estimated: $($item.est) overtime: $($elapsed - [timespan]::Parse($item.est))"

}
new-alias pop remove-stackitem

function get-stackitem {
    param($stackname = "default") 

    $stack = @(import-cache -container "stack.$stackname" -dir (get-syncdir))
    if ($stack -eq $null -or $stack.length -eq 0) { return $null }
    $item = $stack[$stack.length-1]
    return $item
}
new-alias peek get-stackitem

function get-stack {
    param($stackname = "default", [switch][bool] $short) 

    $stack = import-cache -container "stack.$stackname" -dir (get-syncdir)
    if ($short) {
        return $stack | select no,value,ts,est
    } else {
        return $stack
    }
}


function remove-stack {
    [Cmdletbinding(SupportsShouldProcess=$true)]
    param($stackname = "default") 
    if ($PSCmdlet.ShouldProcess("Will remove stack named '$stackname'")) {
        remove-cache -container "stack.$stackname" -dir (get-syncdir)
    }    
}

function invoke-stackcmd {
    [Cmdletbinding(DefaultParameterSetName="add")]
    param(
        [Parameter(mandatory=$false,ParameterSetName="cmd",Position=1)]
        [ValidateSet("push","pop","show","search","remove","done","list","showall")]
        $cmd,
        [Parameter(mandatory=$false,ParameterSetName="add",Position=1)]
        [Parameter(mandatory=$false,ParameterSetName="cmd",Position=2)]
        $what,                 
        [Parameter(mandatory=$true,ParameterSetName="search")]
        $search,
        [Parameter(mandatory=$false,ParameterSetName="add")]
        [Parameter(mandatory=$false,ParameterSetName="cmd")]
        [switch][bool]$go,
        [Parameter(mandatory=$false,ParameterSetName="add")]
        [Parameter(mandatory=$false,ParameterSetName="list")]
        [switch][bool]$done,
        [Parameter(mandatory=$false,ParameterSetName="add")]
        [switch][bool]$remove,
        [Alias("l")]
        [Parameter(mandatory=$false,ParameterSetName="add")]
        [switch][bool]$list,
        [Parameter(mandatory=$false,ParameterSetName="add")]
        [switch][bool]$all,
        [Alias("n")][Alias("name")]
        [Parameter(mandatory=$false)]$stackname = "default",
        [Alias("est")]
        [Parameter(mandatory=$false,ParameterSetName="add")]
        $estimatedTime = $null,
        [alias("c")]
        [switch][bool]$asChild,
        [alias("i")]
        [switch][bool]$interruption,
        [switch][bool]$full
    ) 

    $pipelinemode = $PSCmdlet.MyInvocation.PipelineLength -gt 1
    $command = $cmd
    if ($what -ne $null -and $what -in @("push","pop","show","search","remove","done","list","showall")) {
        $command = $what
        $what = $null        
    }    
    if ($command -eq $null) {
        switch($PSCmdlet.ParameterSetName) {
            { $_ -eq "add" -and !$done -and !$remove } { 
                if ($what -eq $null) {
                    if ($list -or $all) {
                        $command = "list"
                    } else {
                        $command = "show"
                    }
                }
                else {
                    if ($what.gettype() -eq [int] -or $what -match "^#[0-9]+$") {
                        $command = "search"
                        $search = $what
                    }    
                    else {                        
                        $command = "push"
                    } 
                }
            }
            "list" { $command = "show" }
            { $_ -eq "search" -or ($_ -eq "add" -and ($done -or $remove)) } 
            {
                if ($done) { $command = "done" }
                elseif ($remove) { $command = "remove" }
                else { $command = "search" }
            }

        }    
    }

    switch($command) {
        "push" {             
            if ($go) {
                if ($what.gettype() -eq [int]) {
                    $found = idea -search $what
                    if ($found -eq $null) { return }
                    $what = $found
                }                 
                else {
                    push $what -stackname $stackname -estimatedTime $estimatedTime -asChild:$aschild -interruption:$interruption
                    $what = peek -stackname $stackname
                }
                push "idea #$($what.no): $($what.value)" -asChild:$aschild -interruption:$interruption
            } else {
                push $what -stackname $stackname -estimatedTime $estimatedTime -asChild:$aschild -interruption:$interruption
            }
        }
        "pop" {
            pop -stackname $stackname         
        }
        "show" {
            $short = !$full -and !$pipelinemode
            if ($done) {
                $stack = get-stack -stackname "$stackname.done" -short:$short
            } else {
                $stack = get-stack -stackname $stackname -short:$short   
            }
            return $stack
        }
        { $_ -in "list","showall" } {
            $files = get-childitem (get-syncdir) -Filter "stack.*"
            $stacks = $files | % {
                if ($_.name -match "stack\.(.*)\.json" -and $_.name -notmatch "\.done\.json") {
                        return $matches[1]
                }
            }
            if ($all) {
                foreach ($s in $stacks) {
                    write-host "== $s =="
                    get-stack $s | format-table | out-string | write-host
                }
            } else {
            return $stacks
            }
        }
        { $_ -in @("search","remove","done") } {
            $whats = get-stack -stackname $stackname  
            if ($search -eq $null) { $search = $what }

            $id = $null
            if ($search.gettype() -eq [int]) { $id = $search }
            if ($search -match "^\#([0-9]+)$") { $id = [int]::parse($matches[1]) }
            $found = $whats | ? { ($id -ne $null -and $_.no -eq $id) -or ($id -eq $null -and $_.value -match "$search") }
            if ($found -eq $null) {
                if ($search.gettype() -eq [int]) { write-warning "no idea with id $search found" }
                else { write-warning "no idea matching '$search' found" }
                return
            }
            $found = @($found) 

            if ($_ -eq "search") {
                return $found
            }

            if ($found.Length -gt 1) {
                write-warning "more than one idea matching '$search' found:"
                $found | format-table | out-string | write-host
                return
            }                        
            write-verbose "found matching idea: $found" 
            
            if ($done) {
                push $found[0] -stackname "$stackname.done"
                $cur = peek
                if ($cur -ne $null -and $cur -match "idea \#$($found[0].no):") {
                    pop
                }
            }
            if ($done -or $remove) {
                $newstack = $whats | ? { $_.no -ne $found[0].no }
                export-cache -data $newstack -container "stack.$stackname" -dir (get-syncdir)            
            }
        }
    }    
}

function pop-idea {
     pop -stackname "ideas"
}


function todo {
    param(
        [Parameter(mandatory=$true,ParameterSetName="add",Position=1)]
        $what,                 
        [Parameter(mandatory=$true,ParameterSetName="search")]
        $search,
        [Parameter(mandatory=$false,ParameterSetName="add")]
        [switch][bool]$go,
        [Parameter(mandatory=$false,ParameterSetName="add")]
        [Parameter(mandatory=$false,ParameterSetName="list")]
        [switch][bool]$done,
        [Parameter(mandatory=$false,ParameterSetName="add")]
        [switch][bool]$remove
        )

    stack @PSBoundParameters -stackname "todo"
}


function idea {
    param(
        [Parameter(mandatory=$true,ParameterSetName="add",Position=1)]
        $what,                 
        [Parameter(mandatory=$true,ParameterSetName="search")]
        $search,
        [Parameter(mandatory=$false,ParameterSetName="add")]
        [switch][bool]$go,
        [Parameter(mandatory=$false,ParameterSetName="add")]
        [Parameter(mandatory=$false,ParameterSetName="list")]
        [switch][bool]$done,
        [Parameter(mandatory=$false,ParameterSetName="add")]
        [switch][bool]$remove
        )

    stack @PSBoundParameters -stackname "ideas"
}


function stack {
    [Cmdletbinding(DefaultParameterSetName="add")]
    param(
        [Parameter(mandatory=$false,ParameterSetName="cmd",Position=1)]
        [ValidateSet("push","pop","show","search","remove","done","list","showall")]
        $cmd,
        [Parameter(mandatory=$false,ParameterSetName="add",Position=1)]
        [Parameter(mandatory=$false,ParameterSetName="cmd",Position=2)]
        $what,                 
        [Parameter(mandatory=$true,ParameterSetName="search")]
        $search,
        [Parameter(mandatory=$false,ParameterSetName="add")]
        [Parameter(mandatory=$false,ParameterSetName="cmd")]
        [switch][bool]$go,
        [Parameter(mandatory=$false,ParameterSetName="add")]
        [Parameter(mandatory=$false,ParameterSetName="list")]
        [switch][bool]$done,
        [Parameter(mandatory=$false,ParameterSetName="add")]
        [switch][bool]$remove,
        [Alias("l")]
        [Parameter(mandatory=$false,ParameterSetName="add")]
        [switch][bool]$list,
        [Parameter(mandatory=$false,ParameterSetName="add")]
        [switch][bool]$all,
        [Alias("n")][Alias("name")]
        [Parameter(mandatory=$false)]$stackname = "default",
        [Alias("est")]
        [Parameter(mandatory=$false,ParameterSetName="add")]
        $estimatedTime = $null,
        [alias("c")]
        [switch][bool]$asChild,
        [alias("i")]
        [switch][bool]$interruption,
        [switch][bool]$full
    )
    $bound = $PSBoundParameters
    invoke-stackcmd @bound
}

New-Alias "st" stack
New-Alias "stk" stack