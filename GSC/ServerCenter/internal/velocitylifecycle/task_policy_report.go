package velocitylifecycle

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
	"time"
)

// TaskPolicyReview is a side-effect-free analysis of an operator-provided
// SANITIZED JSON report. The JSON is untrusted; in particular, it is not
// evidence of process identity, source authenticity, or user authorization.
type TaskPolicyReview struct {
	Schema int `json:"schema"`
	ReadOnly bool `json:"read_only"`
	Result string `json:"result"`
	AnyAutomaticRestart bool `json:"any_automatic_restart"`
	SourceVerified bool `json:"source_verified"`
	LiveControlAuthorized bool `json:"live_control_authorized"`
	Findings []TaskPolicyFinding `json:"findings"`
}

type TaskPolicyFinding struct {
	Target string `json:"target"`
	RestartCount int `json:"restart_count"`
	AutomaticRestartConfigured bool `json:"automatic_restart_configured"`
	MultipleInstancePolicy string `json:"multiple_instance_policy"`
	Risk string `json:"risk"`
	SafeToStart bool `json:"safe_to_start"`
	SafeToStop bool `json:"safe_to_stop"`
	SafeToRestart bool `json:"safe_to_restart"`
}

type policyBool = *bool
type policyInt = *int

type taskPolicyRaw struct {
	Schema int `json:"schema"`
	Kind string `json:"kind"`
	Synthetic policyBool `json:"synthetic"`
	CollectedAtUTC string `json:"collected_at_utc"`
	ServerStateChanged policyBool `json:"server_state_changed"`
	ScheduledTaskModified policyBool `json:"scheduled_task_modified"`
	ReadOnly policyBool `json:"read_only"`
	LiveControlAuthorized policyBool `json:"live_control_authorized"`
	Result string `json:"result"`
	Instances []taskPolicyRawEntry `json:"instances"`
}
type taskPolicyRawEntry struct {
	ID string `json:"id"`
	TaskPresent policyBool `json:"task_present"`
	TaskCount policyInt `json:"task_count"`
	TaskDefinitionMatchesExpected policyBool `json:"task_definition_matches_expected"`
	TaskState string `json:"task_state"`
	RestartPolicyVerified policyBool `json:"restart_policy_verified"`
	RestartCount policyInt `json:"restart_count"`
	AutomaticRestartConfigured policyBool `json:"automatic_restart_configured"`
	MultipleInstancePolicy string `json:"multiple_instance_policy"`
	TaskToJVMIdentityVerified policyBool `json:"task_to_jvm_identity_verified"`
	LiveControlAuthorized policyBool `json:"live_control_authorized"`
	Result string `json:"result"`
}

// checkDistinctJSONKeys rejects overwritten keys before normal decoding,
// including duplicates deep inside instances[].
func checkDistinctJSONKeys(data []byte) error {
	dec := json.NewDecoder(bytes.NewReader(data))
	var scan func() error
	scan = func() error {
		token, err := dec.Token()
		if err != nil {
			return err
		}
		switch token {
		case json.Delim('{'):
			seen := make(map[string]bool)
			for dec.More() {
				keyToken, err := dec.Token()
				if err != nil { return err }
				key, ok := keyToken.(string)
				if !ok { return errors.New("non-string json object key") }
				if seen[key] { return errors.New("duplicate json key") }
				seen[key] = true
				if err := scan(); err != nil { return err }
			}
			_, err := dec.Token()
			return err
		case json.Delim('['):
			for dec.More() {
				if err := scan(); err != nil { return err }
			}
			_, err := dec.Token()
			return err
		default:
			return nil
		}
	}
	if err := scan(); err != nil { return err }
	if _, err := dec.Token(); err != io.EOF {
		return errors.New("trailing json tokens")
	}
	return nil
}

// ReviewTaskPolicyReport accepts only an in-memory, exact-schema, non-synthetic
// collector report. It NEVER grants any kind of live controller capability.
// Unknown/contradictory/duplicate/missing evidence is a terminal rejection.
func ReviewTaskPolicyReport(data []byte) (TaskPolicyReview, error) {
	if len(data) == 0 || len(data) > 131072 {
		return TaskPolicyReview{}, errors.New("empty or oversized task-policy evidence")
	}
	if err := checkDistinctJSONKeys(data); err != nil {
		return TaskPolicyReview{}, errors.New("invalid or ambiguous task-policy JSON")
	}
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	var raw taskPolicyRaw
	if err := dec.Decode(&raw); err != nil {
		return TaskPolicyReview{}, errors.New("bad task-policy report schema")
	}
	if raw.Schema != 1 ||
		raw.Kind != "GEUMYI_GSC_452_VELOCITY_TASK_RESTART_POLICY" ||
		raw.Synthetic == nil || *raw.Synthetic ||
		raw.ServerStateChanged == nil || *raw.ServerStateChanged ||
		raw.ScheduledTaskModified == nil || *raw.ScheduledTaskModified ||
		raw.ReadOnly == nil || !*raw.ReadOnly ||
		raw.LiveControlAuthorized == nil || *raw.LiveControlAuthorized ||
		len(raw.Instances) != 3 {
		return TaskPolicyReview{}, errors.New("task-policy provenance or safety flags failed")
	}
	when, err := time.Parse(time.RFC3339Nano, raw.CollectedAtUTC)
	if err != nil || when.IsZero() {
		return TaskPolicyReview{}, errors.New("task-policy observation has invalid timestamp")
	}
	expected := []string{"wild", "playground", "other"}
	byTarget := make(map[string]taskPolicyRawEntry, 3)
	for _, entry := range raw.Instances {
		if !validTarget(entry.ID) { return TaskPolicyReview{}, errors.New("unexpected task target") }
		if _, exists := byTarget[entry.ID]; exists {
			return TaskPolicyReview{}, errors.New("duplicate task target")
		}
		byTarget[entry.ID] = entry
	}
	out := TaskPolicyReview{
		Schema:1, ReadOnly:true, SourceVerified:false,
		LiveControlAuthorized:false, Result:"BLOCKED_LIVE_CONTROL",
		Findings:make([]TaskPolicyFinding, 0, 3),
	}
	for _, target := range expected {
		e, ok := byTarget[target]
		if !ok ||
			e.TaskPresent == nil || !*e.TaskPresent ||
			e.TaskCount == nil || *e.TaskCount != 1 ||
			e.TaskDefinitionMatchesExpected == nil || !*e.TaskDefinitionMatchesExpected ||
			e.TaskState != "Running" ||
			e.RestartPolicyVerified == nil || !*e.RestartPolicyVerified ||
			e.RestartCount == nil || *e.RestartCount < 0 || *e.RestartCount > 99999 ||
			e.AutomaticRestartConfigured == nil ||
			*e.AutomaticRestartConfigured != (*e.RestartCount > 0) ||
			e.MultipleInstancePolicy != "IgnoreNew" ||
			e.TaskToJVMIdentityVerified == nil || *e.TaskToJVMIdentityVerified ||
			e.LiveControlAuthorized == nil || *e.LiveControlAuthorized {
			return TaskPolicyReview{}, fmt.Errorf("unverified scheduler state for %s", target)
		}
		risk := "RESTART_POLICY_ZERO_STILL_NO_GO"
		expectedResult := "POLICY_OBSERVED_LIVE_IDENTITY_UNVERIFIED"
		if *e.RestartCount > 0 {
			risk = "AUTO_RESTART_RISK_NO_GO"
			expectedResult = risk
			out.AnyAutomaticRestart = true
		}
		if e.Result != expectedResult {
			return TaskPolicyReview{}, fmt.Errorf("contradictory scheduler classification for %s", target)
		}
		out.Findings = append(out.Findings, TaskPolicyFinding{
			Target:target, RestartCount:*e.RestartCount,
			AutomaticRestartConfigured:*e.AutomaticRestartConfigured,
			MultipleInstancePolicy:e.MultipleInstancePolicy,
			Risk:risk, SafeToStart:false, SafeToStop:false, SafeToRestart:false,
		})
	}
	expectedResult := "TASK_POLICIES_CAPTURED_CONTROL_UNVERIFIED"
	if out.AnyAutomaticRestart { expectedResult = "AUTO_RESTART_RISK_PRESENT_NO_GO" }
	if strings.TrimSpace(raw.Result) != expectedResult {
		return TaskPolicyReview{}, errors.New("top-level task policy conflicts with observations")
	}
	return out, nil
}
