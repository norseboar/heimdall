import json
import logging
import os

from slackclient import SlackClient
from urllib import parse

from flask import Flask, request

ANNOUNCEMENTS_CHANNEL_ID = os.environ['ANNOUNCEMENTS_CHANNEL_ID']


app = Flask(__name__)


app.config['SLACK_TOKEN'] = os.environ['SLACK_TOKEN']


# If app isn't being run by itself, use gunicorn logger
if __name__ != '__main__':
    gunicorn_logger = logging.getLogger('gunicorn.error')
    app.logger.handlers = gunicorn_logger.handlers
    app.logger.setLevel(gunicorn_logger.level)


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
        sc = SlackClient(app.config['SLACK_TOKEN'])
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
            sc.api_call('chat.postMessage', channel=ANNOUNCEMENTS_CHANNEL_ID,
                        text=text)
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
        sc = SlackClient(app.config['SLACK_TOKEN'])

        message = data['message']

        if 'user' in message:
            user_id = message['user']
            user_resp = sc.api_call('users.info', user=user_id)
            user_name = user_resp['user']['name']
        elif 'username' in message:
            user_name = message['username']
        else:
            user_name = 'None'

        permalink_resp = sc.api_call('chat.getPermalink',
                                     channel=data['channel']['id'],
                                     message_ts=data['message']['ts'])
        permalink = permalink_resp['permalink']

        things_title = u'{} in {}: {}'.format(
            user_name, data['channel']['name'], message['text'][:80])
        things_query = parse.urlencode({
            'title': things_title,
            'notes': permalink,
            'tags': 'slack'
        }, quote_via=parse.quote)

        things_url = parse.urlunparse(('things', 'x-callback-url', 'add', '',
                                       things_query, ''))

        app.logger.info(things_url)
        text = (u'<{}|Add to Things> | <{}|Go to message>\n'
                'From <@{}>\n'
                '{}').format(things_url, permalink, user_name, message['text'])
        sc.api_call('chat.postMessage',
                    channel=u'@{}'.format(data['user']['name']), text=text)

    return ''


if __name__ == '__main__':
    app.run(host='0.0.0.0')
