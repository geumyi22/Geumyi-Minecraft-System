# Other backend

`Other` is the fourth managed Paper role in the Day 10 four-server topology.

## Current role

- Paper 26.3 backend behind Velocity
- Private Java port: `127.0.0.1:25572`
- RCON port: `25577`
- Public alias: Java `25567`, Bedrock UDP `19134`
- Public sessions enter Lobby first; Lobby -> Other restores the previous Other position
- GSC backend `bedrock_port`: `0`

## Component targeting

- Technology 0.1.4: enabled
- Chemistry 0.4.1: enabled
- Playground/Lobby do not receive Technology/Chemistry

Only sanitized role/topology information is tracked here. Live world data, RCON secrets and host-local runtime files are not committed.

## Host verification

On the Day 10 real-host Java E2E, Lobby -> Other, `/lobby`, and Other last-position restoration were user-confirmed PASS, including after the final cutover/reboot sequence.
