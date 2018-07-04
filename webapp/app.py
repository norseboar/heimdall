import json
import os
import re

from slackclient import SlackClient
from urllib import parse

from flask import Flask, request

ANNOUNCEMENTS_CHANNEL_ID = os.environ['ANNOUNCEMENTS_CHANNEL_ID']


app = Flask(__name__)

slack_client = SlackClient(os.environ['SLACK_TOKEN'])


def _slack_api_call(*args, **kwargs):
    response = slack_client.api_call(*args, **kwargs)
    if not response['ok']:
        app.logger.info('Response: %s', response)
        raise RuntimeError('Slack API returned non-ok response')
    return response


def _username_from_match(match):
    user_id = match.group(1)
    resp = _slack_api_call('users.info', user=user_id)
    return u'@{}'.format(resp['user']['name'])


def _remove_message_formatting(message):
    user_ids_pattern = '<@(U.*?)>'
    return re.sub(user_ids_pattern, _username_from_match, message)


@app.route('/')
def hello():
    return 'Hello world!'


@app.route('/events', methods=['GET', 'POST'])
def events():
    data = request.get_json()

    request_type = data['type']

    if request_type == 'url_verification':
        app.logger.info('Received challenge')
        return data['challenge']

    elif request_type == 'event_callback':
        event = data['event']
        app.logger.info('Received event: %s', event)
        text = ''

        if event['type'] == 'channel_created':
            channel = event['channel']
            text = u'<@{}> created <#{}|{}>'.format(channel['creator'],
                                                    channel['id'],
                                                    channel['name'])
        if event['type'] == 'channel_unarchive':
            text = (u'<@{}> unarchived <#{}>.').format(event['user'],
                                                       event['channel'])

        if text:
            _slack_api_call('chat.postMessage',
                            channel=ANNOUNCEMENTS_CHANNEL_ID, text=text)
            return ''
        else:
            app.logger.error('Event, but no response')
            return ''

    else:
        app.logger.error('No action')
        return ''


@app.route('/things', methods=['GET', 'POST'])
def things():
    app.logger.info('things called')
    [payload] = parse.parse_qs(request.get_data())[b'payload']
    data = json.loads(payload)
    app.logger.info(data)

    if data['type'] == 'message_action':
        app.logger.info(data)
        message = data['message']

        if 'user' in message:
            user_id = message['user']
            user_resp = _slack_api_call('users.info', user=user_id)
            user_name = user_resp['user']['name']
        elif 'username' in message:
            user_name = message['username']
        else:
            user_name = 'None'

        permalink_resp = _slack_api_call('chat.getPermalink',
                                         channel=data['channel']['id'],
                                         message_ts=data['message']['ts'])
        permalink = permalink_resp['permalink']

        things_title = _remove_message_formatting(message['text'][:512])[:128]
        things_notes = u'{} in {}\n{}'.format(
            user_name, data['channel']['name'], permalink)
        things_query = parse.urlencode({
            'title': things_title,
            'notes': things_notes,
            'tags': 'slack'
        }, quote_via=parse.quote)

        things_url = parse.urlunparse(('things', 'x-callback-url', 'add', '',
                                       things_query, ''))

        app.logger.info(things_url)
        text = (u'<{}|Add to Things> | <{}|Go to message>\n'
                'From <@{}>\n'
                '{}').format(things_url, permalink, user_name, message['text'])
        _slack_api_call('chat.postMessage',
                        channel=u'@{}'.format(data['user']['name']), text=text)

    return ''
