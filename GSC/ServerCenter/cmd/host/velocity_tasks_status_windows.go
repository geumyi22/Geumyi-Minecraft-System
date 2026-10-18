//go:build windows

package main

import (
    "bytes"
    "context"
    "encoding/json"
    "os/exec"
    "time"
)

// Only THREE pinned Task Scheduler names are accepted, and only state is
// returned. No task XML, process command, PID, SID, keys or usernames leave
// this adapter. Shell script itself contains no mutating Task Scheduler APIs.
// An unreadable/disappeared task fails closed as UNKNOWN.
func observeVelocityTasks(parent context.Context) map[string]string {
    states:=map[string]string{}
    const ps=`$ErrorActionPreference='Stop';$items=@(
        @{ID='wild';Name='Geumyi Day10 Velocity wild'},
        @{ID='playground';Name='Geumyi Day10 Velocity playground'},
        @{ID='other';Name='Geumyi Day10 Velocity other'});
        $out=@(foreach($x in $items){
          $state='UNKNOWN';
          try{$task=Get-ScheduledTask -TaskName $x.Name -TaskPath '\' -ErrorAction Stop;
          if($task){$state=[string]$task.State}}catch{}
          [pscustomobject]@{id=$x.ID;state=$state}
        });
        ConvertTo-Json -InputObject $out -Compress -Depth 3`
    ctx,cancel:=context.WithTimeout(parent,5*time.Second)
    defer cancel()
    cmd:=exec.CommandContext(ctx,"powershell.exe",
        "-NoProfile","-NonInteractive","-Command",ps)
    // Fail closed on stderr/noisy shell and never echo process internals.
    output,err:=cmd.Output()
    if err!=nil || len(output)==0 || len(output)>4096 || ctx.Err()!=nil{
        return states
    }
    var rows []struct{
        ID string `json:"id"`
        State string `json:"state"`
    }
    decoder:=json.NewDecoder(bytes.NewReader(output))
    decoder.DisallowUnknownFields()
    if err=decoder.Decode(&rows);err!=nil || len(rows)!=3{return states}
    for _,row:=range rows {
        if _,duplicate:=states[row.ID];duplicate{return map[string]string{}}
        switch row.ID {
        case "wild","playground","other":states[row.ID]=row.State
        default:return map[string]string{}
        }
    }
    return states
}
