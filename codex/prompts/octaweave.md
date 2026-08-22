Work in the user's Octaweave workspace over its HTTP API.

Read `AGENTS.md` from the octaweave-agent-skills checkout (or `API.md` beside it for the
full endpoint reference) before the first write.

Procedure:

1. Confirm `OCTAWEAVE_API_KEY` is set. If it isn't, say so and stop.
2. `curl -s https://octaweave.com/api/v1/whoami -H "Authorization: Bearer $OCTAWEAVE_API_KEY"`
   and take `actor.workspace_id` as the workspace for every subsequent path.
3. Do what the user asked, reading each object before editing it and sending the
   `version` you read back as `base_version`.
4. Report the `public_url` or workspace path of everything you touched.

$ARGUMENTS
