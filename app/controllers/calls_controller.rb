class CallsController < ApplicationController
  include ApplicationHelper
  skip_before_action :verify_authenticity_token
  @@url = 'http://f784f662.ngrok.io'
  Rails.logger = Logger.new(STDOUT)

  def start
    session = Session.new
    session.user.name = create_username
    session.conference.name = 'conference_' + session.user.name
    logger.debug 'user endpoint is ' + session.user.name
    session.user.number = params['From']
    logger.debug 'session number' + session.user.number
    logger.debug 'inside start'
    session.user.sid = params['CallSid']
    logger.debug 'user callsid ' + session.user.sid
    start_conference = StartConference.new(session.user.name)
    response = VoiceResponse.new(start_conference, session)
    store_session(session.user.name, session)
    render xml: response.xml
  end

  def dial
    boot_twilio
    logger.debug 'user params' + params['user']
    session = fetch_session(params[:user])
    session.business.number = params['Digits']
    logger.debug 'dial name' + session.user.name
    call = @@client.calls.create(
      url: @@url + "/calls/answered" + '/' + session.user.name,
      to: session.business.number,
      from: session.user.number)
    forward_call = ForwardCall.new(session.business.number, session.user.name)
    response = VoiceResponse.new(forward_call, session)
    store_session(session.user.name, session)
    render xml: response.xml

  end

  def answered
    session = fetch_session(params[:user])
    session.business.sid = params['CallSid']
    logger.debug 'business callsid ' + session.business.sid
    answered_msg = Answered.new
    response = VoiceResponse.new(answered_msg, session)
    store_session(session.user.name, session)
    render xml: response.xml
  end

  def conference
    session = fetch_session(params[:user])
    @event = params["StatusCallbackEvent"]
    if @event == "participant-leave" and params['CallSid'] == session.user.sid
      logger.debug 'conference sid: ' + session.conference.sid
      logger.debug 'user left conference'
    end

    if @event == "participant-leave" and params['CallSid'] == session.business.sid
      logger.debug 'end the whole thing, the business hung up'
      hangup_user(session)
    end

    if @event == "participant-join"
      logger.debug 'someone is joining the conference'
      if params["CallSid"] == session.user.sid
        logger.debug 'user is joining the conference'
        logger.debug 'their callsid is ' + params['CallSid']
        session.conference.sid = params['ConferenceSid']
        logger.debug 'conference Sid is:' + session.conference.sid
        user = @@client.conferences(session.conference.sid).fetch
        logger.debug 'here' + user.friendly_name
        announce = @@client.conferences(session.conference.sid).participants(session.user.sid).update(announce_url: @@url + "/calls/connect" + '/' + session.user.name)
      end
      if params["CallSid"] == session.business.sid
        logger.debug 'business is joining the conference'
        logger.debug 'their callsid is ' + params['CallSid']
      end
    end
    store_session(session.user.name, session)
  end

  def wait_for_me
    session = fetch_session(params[:user])
    #detect when off hold
    #call user back
    call = @@client.calls.create(
      url: @@url + "/calls/rejoin_conference/" + session.user.name,
      from: session.business.number,
      to: session.user.number
    )
    store_session(session.user.name, session)
    #join conference
  end

  def connect
    session = fetch_session(params[:user])
    announce = Announcement.new
    response = VoiceResponse.new(announce, session)
    render xml: response.xml
  end

  def confirm_wait
    session = fetch_session(params[:user])
    input = params['Digits']
    confirm_wait = ConfirmWait.new(input, session.user.name)
    response = VoiceResponse.new(confirm_wait, session)
    render xml: response.xml
  end

  def hangup
    response = Twilio::TwiML::VoiceResponse.new do |response|
      response.hangup
    end
    wait_for_me
    render xml: response.to_s
  end

  def rejoin_conference
    session = fetch_session(params[:user])
    session.user.sid = params['CallSid']
    rejoin_conference = RejoinConference.new
    response = VoiceResponse.new(rejoin_conference, session)
    store_session(session.user.name, session)
    render xml: response.xml
  end

  def check_wait_or_exit
    session = fetch_session(params[:user])
    if params['CallStatus'] == 'completed'
      logger.debug 'user call completed, hang up business'
        hangup_business(session)
    else
      logger.debug 'user call not completed'
      response = Twilio::TwiML::VoiceResponse.new do |response|
        response.gather(action: '/calls/confirm_wait'+ '/' + session.user.name, method: 'POST', numdigits: 2)
        response.redirect('/calls/rejoin_conference' + '/' + session.user.name)
      end
      render xml: response.to_s
    end
  end

  def hangup_business(session)
    @@client.calls(session.business.sid).update(status: 'completed')
  end

  def hangup_user(session)
    @@client.calls(session.user.sid).update(status: 'completed')
  end

  def status_change
    #status changes only for user, not the business
    callsid = params['CallSid']
    status = params['CallStatus']
    logger.debug 'call status changed'
    logger.debug 'call sid:' + callsid
    if status == 'completed'
      logger.debug 'user status is complete'
    end
  end


  private
  def boot_twilio
    account_sid = 'AC14a0fc7958eb5a457b937744ac590ac4'
    auth_token = '1ac75e253415d780d1a29466adfaee02'
    @@client = Twilio::REST::Client.new(account_sid, auth_token)
  end
end
