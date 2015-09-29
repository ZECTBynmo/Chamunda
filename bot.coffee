monitorPort = 5050
socketPort = 5051

io = require('socket.io')(socketPort)
http = require 'http'
extend = require 'extend'
express = require 'express'
AgarioClient = require 'agario-client'

region = 'US-Atlanta'
client = new AgarioClient 'worker'
interval_id = 0

app = express()

app.get '/', (req, res) ->
  res.send """
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="UTF-8">
        <title>AGAR BOT MONITOR</title>
        <script src="https://cdnjs.cloudflare.com/ajax/libs/d3/3.5.6/d3.js"></script>
        <script src="https://cdnjs.cloudflare.com/ajax/libs/socket.io/1.3.7/socket.io.js"></script>
      </head>
      <body>
        <div class="container"></div>
        <script>
          var sampleSVG;
          var height = 1000;
          var width = 1000;

          sampleSVG = d3.select('.container').append('svg').attr('width', width).attr('height', height);

          function update(state) {
            d3.selectAll("svg > *").remove();

            for(var iBall in state.self) {
              var ballId = state.self[iBall];
              var ball = state.balls[ballId];
              var xLoc = ((ball.x + 10000) / 20000) * width;
              var yLoc = ((ball.y + 10000) / 20000) * height;
              var radius = (ball.size / 20000) * width + 20

              sampleSVG.append('circle').style('stroke', 'gray').style('fill', '#fff').attr('r', radius).attr('cx', xLoc).attr('cy', yLoc).on('mouseover', function() {
                d3.select(this).style('fill', 'aliceblue');
              }).on('mouseout', function() {
                d3.select(this).style('fill', 'white');
              });
            }

            for(var iBall in state.balls) {
              var ball = state.balls[iBall];
              var xLoc = ((ball.x + 10000) / 20000) * width;
              var yLoc = ((ball.y + 10000) / 20000) * height;
              var radius = (ball.size / 20000) * width

              sampleSVG.append('circle').style('stroke', 'gray').style('fill', ball.color).attr('r', radius).attr('cx', xLoc).attr('cy', yLoc).on('mouseover', function() {
                d3.select(this).style('fill', 'aliceblue');
              }).on('mouseout', function() {
                d3.select(this).style('fill', 'white');
              });
            }
          }

          var socket = io('http://localhost:#{socketPort}');
          socket.on('connect', function(){ console.log("connect") });
          socket.on('state', function(data){ console.log("event", data); update(data); });
          socket.on('disconnect', function(){ console.log("disconnect") });
        </script>
      </body>
    </html>
  """

server = app.listen monitorPort, ->
  host = 'localhost'
  port = monitorPort
  console.log 'Example app listening at http://%s:%s', host, port

io.on 'connection', (socket) ->

  recalculateTarget = ->
    candidate_ball = null

    currentBalls = {}
    for id, ball of client.balls
      ballCopy = extend true, {}, ball
      delete ballCopy.client
      currentBalls[id] = ballCopy

    socket.emit 'state',
      balls: JSON.parse JSON.stringify(currentBalls)
      self: client.my_balls

    # first we don't have candidate to eat
    candidate_distance = 0
    my_ball = client.balls[client.my_balls[0]]
    # we get our first ball. We don't care if there more then one, its just example.
    if !my_ball
      return
    # if our ball not spawned yet then we abort. We will come back here in 100ms later
    for ball_id of client.balls
      # we go true all balls we know about
      ball = client.balls[ball_id]
      if ball.virus
        continue
      # if ball is a virus (green non edible thing) then we skip it
      if !ball.visible
        continue
      # if ball is not on our screen (field of view) then we skip it
      if ball.mine
        continue
      # if ball is our ball - then we skip it
      if ball.isMyFriend()
        continue
      # this is my friend, ignore him (implemented by custom property)
      if ball.size / my_ball.size > 0.5
        continue
      # if ball is bigger than 50% of our size - then we skip it
      distance = getDistanceBetweenBalls(ball, my_ball)
      # we calculate distances between our ball and candidate
      if candidate_ball and distance > candidate_distance
        continue
      # if we do have some candidate and distance to it smaller, than distance to this ball, we skip it
      candidate_ball = ball
      # we found new candidate and we record him
      candidate_distance = getDistanceBetweenBalls(ball, my_ball)
      # we record distance to him to compare it with other balls
    if !candidate_ball
      return
    # if we didn't find any candidate, we abort. We will come back here in 100ms later
    client.log 'closest ' + candidate_ball + ', distance ' + candidate_distance
    client.moveTo candidate_ball.x, candidate_ball.y

  getDistanceBetweenBalls = (ball_1, ball_2) ->
    #this calculates distance between 2 balls
    Math.sqrt (ball_1.x - (ball_2.x)) ** 2 + (ball_2.y - (ball_1.y)) ** 2

  client.debug = 0
  #setting debug to 1 (avaialble 0-5)
  client.facebook_key = ''

  AgarioClient::addFriend = (ball_id) ->
    #adding client.addFriend(ball_id) function
    ball = client.balls[ball_id]
    ball.is_friend = true
    #set ball.is_friend to true
    ball.on 'destroy', ->
      #when this friend will be destroyed
      client.emit 'friendLost', ball
      #emit friendEaten event
      return
    client.emit 'friendAdded', ball_id
    #emit friendAdded event
    return

  AgarioClient.Ball::isMyFriend = ->
    #adding ball.isMyFriend() funtion
    @is_friend == true
    #if ball is_friend is true, then true will be returned

  client.on 'ballAppear', (ball_id) ->
    #when we somebody
    ball = client.balls[ball_id]
    if ball.mine
      return
    #this is mine ball
    if ball.isMyFriend()
      return
    #this ball is already a friend
    if ball.name == 'agario-client'
      client.addFriend ball_id

  client.on 'friendLost', (friend) ->
    client.log 'I lost my friend: ' + friend

  client.on 'friendAdded', (friend_id) ->
    friend = client.balls[friend_id]
    client.log 'Found new friend: ' + friend + '!'

  client.once 'leaderBoardUpdate', (old, leaders) ->
    # when we receive leaders list. Fire only once
    name_array = leaders.map (ball_id) ->
      # converting leader's IDs to leader's names
      client.balls[ball_id].name or 'unnamed'

    client.log 'leaders on server: ' + name_array.join(', ')
    return
  client.on 'mineBallDestroy', (ball_id, reason) ->
    if reason.by
      client.log client.balls[reason.by] + ' ate my ball'
    if reason.reason == 'merge'
      client.log 'my ball ' + ball_id + ' merged with my other ball, now i have ' + client.my_balls.length + ' balls'
    else
      client.log 'i lost my ball ' + ball_id + ', ' + client.my_balls.length + ' balls left'

  client.on 'myNewBall', (ball_id) ->
    client.log 'my new ball ' + ball_id + ', total ' + client.my_balls.length

  client.on 'lostMyBalls', ->
    client.log 'lost all my balls, respawning'
    client.spawn 'poop'

  client.on 'somebodyAteSomething', (eater_ball, eaten_ball) ->
    ball = client.balls[eater_ball]
    # get eater ball
    if !ball
      return
    # if we don't know than ball, we don't care
    if !ball.mine
      return

    # if it's not our ball, we don't care
    client.log 'I ate ' + eaten_ball + ', my new size is ' + ball.size

  client.on 'connected', ->
    # when we connected to server
    client.log 'spawning'
    client.spawn 'poop'
    
    # spawning new ball
    interval_id = setInterval(recalculateTarget, 10)

  client.on 'connectionError', (e) ->
    client.log 'Connection failed with reason: ' + e
    client.log 'Server address set to: ' + client.server + ' please check if this is correct and working address'

  client.on 'reset', ->
    clearInterval interval_id

  console.log 'Requesting server in region ' + region
  AgarioClient.servers.getFFAServer { region: region }, (srv) ->
    #requesting FFA server
    if !srv.server
      return console.log('Failed to request server (error=' + srv.error + ', error_source=' + srv.error_source + ')')
    console.log 'Connecting to ' + srv.server + ' with key ' + srv.key
    client.connect 'ws://' + srv.server, srv.key
    #do not forget to add ws://
    return
