local debug
local fonts
local joystick
local planets
local ship
local maxThrust
local friction
local trajectory
local orbit
local map
local currentDestination
local points
local sounds
local lowPointsThreshold

local lg = love.graphics
local lk = love.keyboard
local lt = love.timer

local function copy(obj, seen)
  if type(obj) ~= 'table' then return obj end
  if seen and seen[obj] then return seen[obj] end
  local s = seen or {}
  local res = setmetatable({}, getmetatable(obj))
  s[obj] = res
  for k, v in pairs(obj) do res[copy(k, s)] = copy(v, s) end
  return res
end

local function lerp(x, a, frac)
  return x + (a - x) * frac
end

local function clamp(min, val, max)
  return math.max(min, math.min(val, max));
end

local function vangle(v1, v2)
  local a = math.atan2(v2.y, v2.x) - math.atan2(v1.y, v1.x)
  return (a + math.pi) % (math.pi * 2) - math.pi
end

local function setNewDestination()
  currentDestination = {}
  currentDestination.planet = math.random(#planets)
  local planet = planets[currentDestination.planet]
  local distance = math.sqrt(
    (planet.position.x - ship.position.x) ^ 2 +
    (planet.position.y - ship.position.y) ^ 2
  )
  currentDestination.points = math.floor(distance)
  currentDestination.start = lt.getTime()
end

function love.load()
  debug  = false

  fonts  = {
    label = lg.newFont(14),
    value = lg.newFont(18)
  }

  sounds = {
    burn = love.audio.newSource("assets/engine.wav", "static"),
    oneup = love.audio.newSource("assets/oneup.wav", "static"),
    warning = love.audio.newSource("assets/warning.wav", "static"),
    timeout = love.audio.newSource("assets/timeout.wav", "static"),
    bounce = love.audio.newSource("assets/bounce.wav", "static")
  }
  sounds.burn:setVolume(0)
  sounds.burn:setLooping(true)
  sounds.burn:play()

  local joysticks = love.joystick.getJoysticks()
  joystick = joysticks[1]

  points = 0
  lowPointsThreshold = 400
  maxThrust = 105
  friction = 50

  map = {
    width = 8000,
    height = 2000
  }

  planets = {
    {
      position = { x = 200, y = 500 },
      radius = 80,
      mass = 4000000
    },
    {
      position = { x = 1200, y = 800 },
      radius = 60,
      mass = 3000000
    },
    {
      position = { x = 1500, y = 1500 },
      radius = 80,
      mass = 4000000
    },
    {
      position = { x = 2100, y = 1000 },
      radius = 60,
      mass = 3000000
    },
    {
      position = { x = 450, y = 100 },
      radius = 30,
      mass = 1500000
    },
    {
      position = { x = 1200, y = 300 },
      radius = 60,
      mass = 3000000
    },
    {
      position = { x = 2000, y = 1600 },
      radius = 80,
      mass = 4000000
    },
    {
      position = { x = 2300, y = 400 },
      radius = 60,
      mass = 3000000
    },
    {
      position = { x = 3000, y = 900 },
      radius = 80,
      mass = 4000000
    },
    {
      position = { x = 2500, y = 1600 },
      radius = 60,
      mass = 3000000
    },
    {
      position = { x = 3500, y = 1600 },
      radius = 30,
      mass = 1500000
    },
    {
      position = { x = 3400, y = 300 },
      radius = 60,
      mass = 3000000
    }
  }

  ship = {
    position = { x = planets[1].position.x + 100, y = planets[1].position.y },
    velocity = { x = 0, y = -200 },
    turnAngle = math.pi / 4,
    thrust = 0,
    radius = 10,
    mass = 1,
    orbiting = false,
    orbitingPlanet = nil,
  }

  trajectory = {}
  orbit = 20

  setNewDestination()
end

local function getGravity(centralBody, satelliteBody)
  local diff = {
    x = centralBody.position.x - satelliteBody.position.x,
    y = centralBody.position.y - satelliteBody.position.y
  }
  local distance = math.max(math.sqrt((diff.x ^ 2) + (diff.y ^ 2)), centralBody.radius)
  local direction = { x = diff.x / distance, y = diff.y / distance }
  local force = (satelliteBody.mass * centralBody.mass) / (distance ^ 2)

  return { x = direction.x * force, y = direction.y * force }
end

local function updateSatellite(satellite, dt)
  local speed = math.sqrt((satellite.velocity.x ^ 2) + (satellite.velocity.y ^ 2))
  local direction = { x = satellite.velocity.x / speed, y = satellite.velocity.y / speed }

  local pull = { x = 0, y = 0 }
  for _, planet in ipairs(planets) do
    local gravity = getGravity(planet, satellite)
    pull = { x = pull.x + gravity.x, y = pull.y + gravity.y }
  end

  local newVelocity = {
    x = satellite.velocity.x + direction.x * (satellite.thrust - friction) * dt + pull.x * dt,
    y = satellite.velocity.y + direction.y * (satellite.thrust - friction) * dt + pull.y * dt
  }

  local newPosition = {
    x = satellite.position.x + satellite.velocity.x * dt,
    y = satellite.position.y + satellite.velocity.y * dt
  }

  if satellite.orbiting then
    local planet = planets[satellite.orbitingPlanet]
    local orbitVector = {
      x = planet.position.x - satellite.position.x,
      y = planet.position.y - satellite.position.y
    }
    local distance = math.sqrt(orbitVector.x ^ 2 + orbitVector.y ^ 2)
    local orbitUnit = {
      x = orbitVector.x / distance,
      y = orbitVector.y / distance
    }
    local approachAngle = vangle(orbitVector, satellite.velocity)
    local orbitAngle = math.atan2(orbitUnit.y, orbitUnit.x)
    local orbitSpeed = math.max(100, math.sqrt(satellite.velocity.x ^ 2 + satellite.velocity.y ^ 2))
    local orbitDireciton = approachAngle >= 0 and 1 or -1
    local orbitingVelocity = {
      x = math.cos(orbitAngle + orbitDireciton * math.pi / 2) * orbitSpeed,
      y = math.sin(orbitAngle + orbitDireciton * math.pi / 2) * orbitSpeed,
    }
    local orbitingPosition = {
      x = satellite.position.x + orbitingVelocity.x * dt,
      y = satellite.position.y + orbitingVelocity.y * dt
    }

    local orbitingDistance = math.sqrt(
      (orbitingPosition.x - planet.position.x) ^ 2 + (orbitingPosition.y - planet.position.y) ^ 2
    )

    local normalDistance = math.sqrt(
      (newPosition.x - planet.position.x) ^ 2 + (newPosition.y - planet.position.y) ^ 2
    )

    if orbitingDistance > normalDistance then
      newVelocity = orbitingVelocity
      newPosition = orbitingPosition
    end
  end

  satellite.velocity = newVelocity
  satellite.position = newPosition
end

local function sample(satellite)
  local sampled = copy(satellite)
  local speed = math.floor(math.sqrt(
    satellite.velocity.x ^ 2 + satellite.velocity.y ^ 2
  ))
  local sampleCount = 20
  if speed >= 0.1 then
    sampled.thrust = 0
  else
    sampled.thrust = maxThrust / 2
    sampleCount = 10
  end

  sampled.orbiting = false

  local samples = {}
  for n = 1, sampleCount do
    updateSatellite(sampled, 0.2)
    for _, planet in ipairs(planets) do
      local diff = {
        x = planet.position.x - sampled.position.x,
        y = planet.position.y - sampled.position.y
      }
      local distance = math.sqrt(diff.x ^ 2 + diff.y ^ 2)
      if distance < planet.radius + orbit then
        return samples
      end
    end
    table.insert(samples, { x = math.floor(sampled.position.x), y = math.floor(sampled.position.y) })
  end

  return samples
end

function love.update(dt)
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
    ship.thrust = lerp(ship.thrust, maxThrust, 0.1)
  else
    ship.thrust = lerp(ship.thrust, 0, 0.2)
  end

  if ship.thrust > 0.1 then
    sounds.burn:setVolume(ship.thrust / maxThrust)
  else
    sounds.burn:setVolume(0)
  end

  if ship.orbiting then
    local planet = planets[ship.orbitingPlanet]
    local orbitVector = {
      x = planet.position.x - ship.position.x,
      y = planet.position.y - ship.position.y
    }
    local distance = math.sqrt(orbitVector.x ^ 2 + orbitVector.y ^ 2)

    if distance > ship.radius + planet.radius + orbit + 10 then
      ship.orbiting = false
    end
  else
    for planetIndex, planet in ipairs(planets) do
      local orbitVector = {
        x = planet.position.x - ship.position.x,
        y = planet.position.y - ship.position.y
      }
      local distance = math.sqrt(orbitVector.x ^ 2 + orbitVector.y ^ 2)
      local approachAngle = vangle(orbitVector, ship.velocity)
      local speed = math.sqrt(ship.velocity.x ^ 2 + ship.velocity.y ^ 2)

      if distance <= ship.radius + planet.radius + orbit then
        if math.abs(approachAngle) < 10 and speed > 300 then
          sounds.bounce:play()
        end
        ship.orbiting = true
        ship.orbitingPlanet = planetIndex
        ship.velocity = {
          x = ship.velocity.x * 0.8,
          y = ship.velocity.y * 0.8
        }
        if planetIndex == currentDestination.planet then
          points = points + currentDestination.points
          sounds.oneup:play()
          setNewDestination()
        end
        break
      end
    end
  end

  updateSatellite(ship, dt)

  trajectory = sample(ship)

  local speed = math.floor(math.sqrt(
    ship.velocity.x ^ 2 + ship.velocity.y ^ 2
  ))

  local velocityAngle
  if #trajectory == 0 or speed >= 0.1 then
    velocityAngle = math.atan2(ship.velocity.y, ship.velocity.x)
  else
    local lastTrajectory = trajectory[#trajectory]
    local diff = {
      x = lastTrajectory.x - ship.position.x,
      y = lastTrajectory.y - ship.position.y
    }
    speed = math.sqrt(diff.x ^ 2 + diff.y ^ 2)

    velocityAngle = math.atan2(diff.y, diff.x)
  end

  if speed >= 0.1 then
    ship.turnAngle = velocityAngle -- math.atan2(ship.turnAngle, velocityAngle, 0.3)
  end
end

function love.keypressed(key)
  if key == "d" then
    debug = not debug
  elseif key == "q" then
    love.event.quit()
  end
end

local function cullBy(entity, container)
  local result = {
    x = clamp(0, entity.x, container.width),
    y = clamp(0, entity.y, container.height),
    culled = false
  }

  if result.x ~= entity.x or result.y ~= entity.y then
    result.culled = true
  end

  return result
end

function love.draw()
  local speed = math.floor(math.sqrt(
    ship.velocity.x ^ 2 + ship.velocity.y ^ 2
  ))

  lg.push()
  lg.translate(-ship.position.x + lg.getWidth() / 2, -ship.position.y + lg.getHeight() / 2)
  for planetIndex, planet in ipairs(planets) do
    lg.setColor(0, 1, 1)
    lg.circle("fill", planet.position.x, planet.position.y, planet.radius)

    if planetIndex == currentDestination.planet then
      lg.setColor(1, 1, 0, 0.2)
      lg.circle("fill", planet.position.x, planet.position.y, planet.radius)
    end

    lg.setColor(0, 0.4, 0.4)
    lg.circle("line", planet.position.x, planet.position.y, planet.radius + orbit)
  end

  lg.push()
  lg.translate(ship.position.x, ship.position.y)
  lg.rotate(ship.turnAngle)
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
      -ship.radius - (ship.thrust / maxThrust) * 8,
      0,
      (ship.thrust / maxThrust) * 8,
      (ship.thrust / maxThrust) * 4
    )
  end
  lg.pop()

  lg.setColor(1, 1, 1)
  for _, point in ipairs(trajectory) do
    lg.points(point.x, point.y)
  end

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
    local show = true
    if planetIndex == currentDestination.planet then
      lg.setColor(1, 1, 0)
      if currentDestination.points < lowPointsThreshold and math.sin(math.pi * lt.getTime() * 4) > 0 then
        show = false
      end
    else
      lg.setColor(0, 1, 1)
    end

    if show then
      lg.circle(
        "fill",
        minimap.x + planet.position.x * minimap.scale,
        minimap.y + planet.position.y * minimap.scale,
        2
      )

      if planetIndex == currentDestination.planet then
        lg.circle(
          "line",
          minimap.x + planet.position.x * minimap.scale,
          minimap.y + planet.position.y * minimap.scale,
          4
        )
      end
    end
  end
  lg.setColor(0, 1, 0)
  local shipPosition = cullBy(ship.position, map)
  if shipPosition.culled then
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
      local pointPosition = cullBy(samplePoint, map)
      if not pointPosition.culled then
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
