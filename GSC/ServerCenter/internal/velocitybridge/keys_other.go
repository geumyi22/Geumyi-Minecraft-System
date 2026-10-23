//go:build !windows

package velocitybridge

import "errors"

// Never fall back to plaintext outside Windows, even though the legacy
// application's generic securestore has a pass-through non-Windows build.
func GenerateUserProtectedProxyKey(target string) (string,error){
    return "",errors.New("Windows current-user DPAPI required")
}
func OpenUserProtectedProxyKey(target,protected string) ([]byte,error){
    return nil,errors.New("Windows current-user DPAPI required")
}
