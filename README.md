# Heimdall
Slack app for watching

Three endpoints:
- /: Hello world (just for testing)
- /events: Listens to events from Slack, supports two (created channel & unarchived channel)
- /things: An action for messages that creates a URL to add a task to Things based on the message

## Development
- Create `slack_token.txt` containing the OAuth Access Token
- Run the app with `docker-compose up`
