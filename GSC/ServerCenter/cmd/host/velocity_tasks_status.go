package main

import (
    "net/http"
    "runtime"
)

// This is the first actual GSC-facing Velocity surface rather than yet
// another standalone diagnostic collector. It reports the Windows Scheduler
// state of the THREE fixed Day10 Velocity proxy tasks on authenticated GET,
// without claiming those states prove a live/healthy Velocity JVM.
//
// Stop and restart are intentionally never offered before the real Velocity
// plugin/player drain and Scheduler restore transaction exist and pass E2E.
type velocityTaskStatus struct {
    Target string `json:"target"`
    TaskState string `json:"task_state"`
    StateSource string `json:"state_source"`
    RunningTask bool `json:"running_task"`
    JVMAuthenticated bool `json:"jvm_authenticated"`
    PlayerSafetyVerified bool `json:"player_safety_verified"`
    CanStart bool `json:"can_start"`
    CanStop bool `json:"can_stop"`
    CanRestart bool `json:"can_restart"`
}

type velocityTaskStatusResponse struct {
    OK bool `json:"ok"`
    ReadOnly bool `json:"read_only"`
    ControlAuthorized bool `json:"control_authorized"`
    Platform string `json:"platform"`
    Result string `json:"result"`
    Tasks []velocityTaskStatus `json:"tasks"`
}

func buildVelocityTaskStatus(states map[string]string) velocityTaskStatusResponse {
    out:=velocityTaskStatusResponse{
        OK:true,ReadOnly:true,ControlAuthorized:false,
        Platform:runtime.GOOS,Result:"GSC_VELOCITY_TASK_OBSERVATION_ONLY_NO_GO",
        Tasks:make([]velocityTaskStatus,0,3),
    }
    for _,id:=range []string{"wild","playground","other"} {
        state:=states[id]
        switch state {
        case "Running","Ready","Disabled","Queued":
        default: state="UNKNOWN"
        }
        out.Tasks=append(out.Tasks,velocityTaskStatus{
            Target:id,TaskState:state,StateSource:"windows_task_scheduler_observation",
            RunningTask:state=="Running",
            JVMAuthenticated:false,PlayerSafetyVerified:false,
            CanStart:false,CanStop:false,CanRestart:false,
        })
    }
    return out
}

// Handler must only be registered behind requireAuth. This route never
// accepts mutating methods, arbitrary task names, command lines or task XML.
func apiV1VelocityTasks(w http.ResponseWriter,r *http.Request) {
    if r.Method!=http.MethodGet {
        http.Error(w,"GET required",http.StatusMethodNotAllowed)
        return
    }
    w.Header().Set("Cache-Control","no-store")
    writeJSON(w,buildVelocityTaskStatus(observeVelocityTasks(r.Context())))
}
