# helpscout-to-gorgias-migration

Ruby scripts to export conversations/threads from HelpScout to MongoDB, then import from MongoDB to Gorgias.

## Installation

1. Install required gems

```
bundle install
```

2. Create an App in HelpScout to access the API: Log into HelpScout, go to Your Profile, click on My Apps, and click on Create My App. You can enter any url for the Redirection URL, as it will not be used. Copy the App ID and App Secret for the new app.

3. Use the HelpScout API client credentials flow to get an API access_token good for 48 hours

```
curl -X POST https://api.helpscout.net/v2/oauth2/token --data "grant_type=client_credentials" --data "client_id=<your-app-ID>" --data "client_secret=<your-app-secret>"
```

4. Create a config.yml and enter valid options including the access_token retrieved in the previous step.

## Usage

### Exporting from HelpScout

To export all of your HelpScout mailboxes, leave the "mailboxes" config attribute blank, or specify individual mailboxes to export (comma separated). Then run:

```
ruby export-helpscout-conversations.rb
```

Resulting conversations and threads will be stored to the MongoDB database specified in the config.yml file.

### Importing to Gorgias

```
ruby import-gorgias-tickets.rb
```

Gorgias API will reject any agent messages that don't match a valid agent email address in your gorgias account. Specify a comma separated list of valid gorgias users and a fallback user for HelpScout threads sent by a user that doesn't match a corresponding user in Gorgias.

Script currently skips threads that do not contain a body (e.g. ticket closed/updated events).