# Security Notes

Do **not** commit real values for any of the following:

- Discord bot tokens
- RCON passwords
- GSC API tokens
- GSCM pairing/device tokens
- GitHub tokens
- Apple certificates, private keys or signing credentials
- Android keystores / signing passwords
- private machine-specific secrets

Commit only sanitized templates such as:

- `agent.properties.example`
- `config.example.json`
- `.env.example`

If a secret is ever committed, rotate the credential first; deleting the file in a later commit is not sufficient by itself.
