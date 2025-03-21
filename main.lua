local debug
local time
local fonts
local sounds
local shaders
local joystick
local baseShip
local map
local planetTemplates
local planets
local ship
local trajectory
local currentDestination
local points
local lowPointsThreshold

local lg = love.graphics
local lk = love.keyboard
local lt = love.timer
local lm = love.math
local b = require("lib/batteries")

local physics = require("physics")

local function setNewDestination()
  local lastPlanet = currentDestination.planet or 0
  local newPlanet = lastPlanet
  local planet
  local distance

  while lastPlanet == newPlanet do
    newPlanet = lm.random(#planets)
    if not planets[newPlanet].orbitable then
      newPlanet = lastPlanet
    else
      planet = planets[newPlanet]
      distance = (planet.position - ship.position):length()

      if distance < 1500 then
        newPlanet = lastPlanet
      end
    end
  end

  currentDestination = {}
  currentDestination.planet = newPlanet

  currentDestination.points = math.floor(distance)
  currentDestination.start = lt.getTime()
end

local function loadAssets()
  sounds = {
    burn = love.audio.newSource("assets/engine.wav", "static"),
    oneup = love.audio.newSource("assets/oneup.wav", "static"),
    warning = love.audio.newSource("assets/warning.wav", "static"),
    timeout = love.audio.newSource("assets/timeout.wav", "static"),
    bounce = love.audio.newSource("assets/bounce.wav", "static"),
    bhole = love.audio.newSource("assets/bhole.wav", "static"),

  }
  sounds.burn:setVolume(0)
  sounds.burn:setLooping(true)
  sounds.burn:play()

  sounds.bhole:setVolume(0)
  sounds.bhole:setLooping(true)
  sounds.bhole:play()

  fonts = {
    label = lg.newFont(14),
    value = lg.newFont(18)
  }

  shaders = {
    planet = lg.newShader("planet.glsl")
  }
end

local function generateMap()
  planets = {}

  -- put 2 black holes on the map
  for i = 1, 2 do
    local position = b.vec2(
      (i - 1) * map.width / 2 + map.width / 6 + lm.random(math.floor(map.width / 6)),
      map.height / 3 + lm.random(math.floor(map.height / 3))
    )

    table.insert(planets, {
      orbitable = false,
      position = position,
      mass = 17000000,
      radius = 120,
      orbit = 0,
      minDistance = 1000
    })
  end

  for _ = 1, 20 do
    local position
    local newPlanet = b.table.deep_copy(planetTemplates[lm.random(#planetTemplates)])
    local attemptsLeft = 1000

    while true do
      position = b.vec2(300 + lm.random(map.width - 600), 300 + lm.random(map.height - 600))

      local fitFound = true
      for _, planet in ipairs(planets) do
        local distance = planet.position:distance(position)

        if distance < planet.minDistance then
          fitFound = false
          break
        end
      end

      if fitFound then
        newPlanet.position = position
        table.insert(planets, newPlanet)
        break
      end

      attemptsLeft = attemptsLeft - 1

      if attemptsLeft == 0 then
        break
      end
    end
  end
end

local function reset()
  generateMap()

  time = 0
  points = 0
  currentDestination = {}
  local lastPlanet = b.table.back(planets)

  ship = b.table.copy(baseShip)
  ship = b.table.overlay(b.table.copy(baseShip), {
    position = b.vec2(
      lastPlanet.position.x + lastPlanet.radius + lastPlanet.orbit,
      lastPlanet.position.y
    ),
    velocity = b.vec2(0, -200),
    turnDirection = b.vec2(0, -1),
    thrust = 0,
    orbiting = false,
    orbitingBody = nil,
    fuel = 100
  })

  trajectory = {}

  setNewDestination()
end

function love.load()
  debug = false

  loadAssets()

  local joysticks = love.joystick.getJoysticks()
  joystick = joysticks[1]

  lowPointsThreshold = 400

  baseShip = {
    mass = 1,
    radius = 10,
    friction = 80,
    maxThrust = 175
  }

  map = {
    width = 8000,
    height = 2000
  }

  -- repetition reflects odds
  planetTemplates = {
    {
      orbitable = true,
      radius = 30,
      orbit = 20,
      mass = 1500000,
      minDistance = 1000
    },
    {
      orbitable = true,
      radius = 60,
      orbit = 20,
      mass = 3000000,
      minDistance = 700
    },
    {
      orbitable = true,
      radius = 60,
      orbit = 20,
      mass = 3000000,
      minDistance = 700
    },
    {
      orbitable = true,
      radius = 60,
      orbit = 20,
      mass = 3000000,
      minDistance = 700
    },
    {
      orbitable = true,
      radius = 80,
      orbit = 20,
      mass = 4000000,
      minDistance = 600
    },
    {
      orbitable = true,
      radius = 80,
      orbit = 20,
      mass = 4000000,
      minDistance = 600
    },
  }

  reset()
end

local function sample(satellite, sampleCount)
  local sampled = b.table.deep_copy(satellite)
  sampled.thrust = 0

  local start = math.ceil(time * 5) / 5
  local diff = start - time
  local samples = {}
  for n = 1, sampleCount do
    local step = n == 1 and diff or 0.2
    physics.updateSatellite(sampled, planets, step)
    for _, planet in ipairs(planets) do
      local distance = (planet.position - sampled.position):length()
      if distance < planet.radius + planet.orbit then
        return samples
      end
    end
    table.insert(samples, sampled.position)
  end

  return samples
end

function love.update(dt)
  time = time + dt
  local now = lt.getTime()

  if now - currentDestination.start >= 3 then
    currentDestination.points = currentDestination.points - 100
    currentDestination.start = now
    if currentDestination.points < lowPointsThreshold and currentDestination.points > 0 then
      sounds.warning:play()
    end
  end

  if currentDestination.points <= 0 then
    sounds.timeout:play()
    setNewDestination()
  end

  local touches = love.touch.getTouches()
  if lk.isDown("up") or (joystick and joystick:isDown(1)) or #touches > 0 then
    ship.thrust = b.math.lerp(ship.thrust, ship.maxThrust, 0.1)
  else
    ship.thrust = b.math.lerp(ship.thrust, 0, 0.2)
  end

  if ship.thrust > 0.1 then
    sounds.burn:setVolume(ship.thrust / ship.maxThrust)
    ship.fuel = ship.fuel - (ship.thrust / ship.maxThrust) * 2 * dt
  else
    sounds.burn:setVolume(0)
  end

  sounds.bhole:setVolume(0)

  for _, bhole in ipairs(planets) do
    if not bhole.orbitable then
      local distance = (bhole.position - ship.position):length()

      if distance < 1000 then
        sounds.bhole:setVolume((1000 - distance) / 1000)
        break
      end
    end
  end

  local currentOrbiting = ship.orbiting

  physics.update({ ship }, planets, dt)

  if not currentOrbiting and ship.orbiting then
    local planet = planets[ship.orbitingBody]
    local approachAngle = (planet.position - ship.position):angle_difference(ship.velocity)
    local speed = ship.velocity:length()
    if math.abs(approachAngle) < 10 and speed > 300 then
      sounds.bounce:play()
    end
    if ship.orbitingBody == currentDestination.planet then
      points = points + currentDestination.points
      sounds.oneup:play()
      setNewDestination()
      ship.fuel = math.min(100, ship.fuel + 50)
    end
  end

  if not ship.orbiting or ship.thrust > ship.maxThrust * 0.9 then
    trajectory = sample(ship, 20)
  else
    trajectory = {}
  end

  ship.turnDirection = b.math.lerp(ship.turnDirection, ship.velocity:normalise(), 0.3)
end

function love.keypressed(key)
  if key == "d" then
    debug = not debug
  elseif key == "q" then
    love.event.quit()
  end
end

local function cullBy(vector, container)
  local culled = false
  local newVector = vector:clamp(b.vec2(0, 0), b.vec2(container.width, container.height))

  if newVector.x ~= vector.x or newVector.y ~= vector.y then
    culled = true
  end

  return newVector, culled
end

function love.draw()
  lg.setBackgroundColor(2 / 255, 6 / 255, 18 / 255)
  local planet = planets[currentDestination.planet]
  local destinationVector = planet.position - ship.position
  local destinationDistance = destinationVector:length()
  local destinationDirection = destinationVector:normalize()

  local speed = math.floor(ship.velocity:length())

  lg.push()
  lg.translate(-ship.position.x + lg.getWidth() / 2, -ship.position.y + lg.getHeight() / 2)
  for planetIndex, planet in ipairs(planets) do
    if planet.orbitable then
      lg.setColor(0, 1, 1)

      -- shader
      shaders.planet:send("iTime", time)
      shaders.planet:send("iResolution", { planet.radius * 2, planet.radius * 2, 1 })
      shaders.planet:send("iCenter", {
        planet.position.x - planet.radius - ship.position.x + lg.getWidth() / 2,
        planet.position.y - planet.radius - ship.position.y + lg.getHeight() / 2,
        1
      })
      lg.setShader(shaders.planet)
      lg.circle("fill", planet.position.x, planet.position.y, planet.radius)
      lg.setShader()
    else
      lg.setColor(0, 0.4, 0.4)
      local currentRadius = 10
      while currentRadius <= planet.radius do
        lg.circle("line", planet.position.x, planet.position.y, currentRadius)
        currentRadius = currentRadius + 10
      end
    end

    if planetIndex == currentDestination.planet then
      lg.setColor(1, 1, 0, 0.2)
      lg.circle("fill", planet.position.x, planet.position.y, planet.radius)
    end

    if planet.orbitable then
      lg.setColor(0, 0.4, 0.4)
      lg.circle("line", planet.position.x, planet.position.y, planet.radius + planet.orbit)
    end
  end

  local destinationVisible =
      (planet.position.x + planet.radius > ship.position.x - lg.getWidth() / 2 and
        planet.position.x - planet.radius < ship.position.x + lg.getWidth() / 2 and
        planet.position.y + planet.radius > ship.position.y - lg.getHeight() / 2 and
        planet.position.y - planet.radius < ship.position.y + lg.getHeight() / 2)

  if not destinationVisible then
    lg.setColor(0, 1, 0, 0.7)
    lg.push()
    local arrowPosition = ship.position + destinationDirection * ship.radius * 16
    lg.translate(arrowPosition.x, arrowPosition.y)
    lg.print(string.format("%5.2f", destinationDistance / 100), ship.radius * 3, 0)
    lg.rotate(destinationDirection:angle())

    lg.polygon(
      "fill",
      ship.radius * 3, 0,
      -ship.radius * 2, -ship.radius * 1.5,
      -ship.radius * 2, ship.radius * 1.5
    )
    lg.pop()
  end

  lg.setColor(0, 1, 0, 0.4)
  for _, point in ipairs(trajectory) do
    lg.circle("line", point.x, point.y, 2)
  end

  lg.push()
  lg.translate(ship.position.x, ship.position.y)

  lg.rotate(ship.turnDirection:angle())
  lg.setColor(0.6, 0.6, 0.6)
  lg.polygon(
    "fill",
    ship.radius, 0,
    -ship.radius, -ship.radius,
    -ship.radius, ship.radius
  )
  lg.setColor(1, 0.2, 0)
  lg.ellipse("fill", 0, 0, ship.radius, ship.radius / 2)
  if ship.thrust > 0.1 then
    lg.setColor(1, 1, 0)
    lg.ellipse(
      "fill",
      -ship.radius - (ship.thrust / ship.maxThrust) * 8,
      0,
      (ship.thrust / ship.maxThrust) * 8,
      (ship.thrust / ship.maxThrust) * 4
    )
  end
  lg.pop()

  lg.pop()

  -- minimap
  local minimap = {
    y = 30,
    width = lg.getWidth() / 3
  }

  minimap.x = lg.getWidth() - 20 - minimap.width
  minimap.scale = minimap.width / map.width
  minimap.height = minimap.scale * map.height

  lg.setColor(0, 0.2, 0.2, 0.5)
  lg.rectangle("fill", minimap.x, minimap.y, minimap.width, minimap.height)
  for planetIndex, planet in ipairs(planets) do
    if planet.orbitable then
      local show = true
      if planetIndex == currentDestination.planet then
        lg.setColor(1, 1, 0)
        if currentDestination.points < lowPointsThreshold and math.sin(math.pi * time * 4) > 0 then
          show = false
        end
      else
        lg.setColor(0, 1, 1)
      end

      local planetRadius = math.ceil(planet.radius / 20)

      if show then
        lg.circle(
          "fill",
          minimap.x + planet.position.x * minimap.scale,
          minimap.y + planet.position.y * minimap.scale,
          planetRadius
        )

        if planetIndex == currentDestination.planet then
          lg.circle(
            "line",
            minimap.x + planet.position.x * minimap.scale,
            minimap.y + planet.position.y * minimap.scale,
            planetRadius + 2
          )
        end
      end
    else
      lg.setColor(0, 1, 1)
      local planetRadius = math.ceil(planet.radius / 20)

      lg.circle(
        "line",
        minimap.x + planet.position.x * minimap.scale,
        minimap.y + planet.position.y * minimap.scale,
        planetRadius
      )
    end
  end
  lg.setColor(0, 1, 0)
  local shipPosition, shipPositionCulled = cullBy(ship.position, map)
  if shipPositionCulled then
    lg.polygon(
      "fill",
      minimap.x + shipPosition.x * minimap.scale - 4,
      minimap.y + shipPosition.y * minimap.scale,

      minimap.x + shipPosition.x * minimap.scale,
      minimap.y + shipPosition.y * minimap.scale - 4,

      minimap.x + shipPosition.x * minimap.scale + 4,
      minimap.y + shipPosition.y * minimap.scale,

      minimap.x + shipPosition.x * minimap.scale,
      minimap.y + shipPosition.y * minimap.scale + 4
    )
  else
    lg.circle(
      "fill",
      minimap.x + shipPosition.x * minimap.scale,
      minimap.y + shipPosition.y * minimap.scale,
      2
    )
  end
  lg.setColor(1, 1, 1)
  for sampleIndex, samplePoint in ipairs(trajectory) do
    if sampleIndex % 4 == 0 then
      local pointPosition, pointPositionCulled = cullBy(samplePoint, map)
      if not pointPositionCulled then
        lg.points(
          minimap.x + pointPosition.x * minimap.scale,
          minimap.y + pointPosition.y * minimap.scale
        )
      end
    end
  end

  local scoreLabel = "SCORE: "
  local nextLabel = "NEXT: "
  local speedLabel = "SPEED: "
  local fuelLabel = "FUEL: "
  lg.setColor(1, 1, 1)
  lg.setFont(fonts.label)
  lg.print(scoreLabel, 10, 10)
  local labelWidth = fonts.label:getWidth(scoreLabel)
  local labelHeight = fonts.label:getHeight(scoreLabel)
  local scoreHeight = fonts.value:getHeight(points)
  if currentDestination.points < lowPointsThreshold then
    lg.setColor(1, 0.2, 0)
  else
    lg.setColor(1, 1, 0)
  end
  lg.print(nextLabel .. currentDestination.points, 10, scoreHeight + 10)
  lg.setColor(1, 1, 0)
  lg.setFont(fonts.value)
  lg.print(points, labelWidth + 10, 10 + 2 - (scoreHeight - labelHeight))
  lg.setColor(1, 1, 1)
  lg.setNewFont(12)
  lg.print(speedLabel .. speed, 10, labelHeight + scoreHeight + 10 + 4)
  lg.setColor(0, 0.2, 1)
  lg.print(fuelLabel .. string.format("%5.2f", ship.fuel), 10, 2 * labelHeight + scoreHeight + 10 + 4)


  -- debug
  lg.setNewFont(12)
  if debug then
    lg.setColor(1, 1, 1)
    lg.print(table.concat({
      "velocity: x = " .. ship.velocity.x .. ", y = " .. ship.velocity.y,
      "orbiting: " .. (ship.orbiting and "true" or "false"),
      "current destination points: " .. currentDestination.points,
      "points: " .. points
    }, "\n"))
  end
end
