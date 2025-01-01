local _M = {}

local b = require("lib/batteries")

local function getGravity(centralBody, satelliteBody)
  local diff = centralBody.position - satelliteBody.position
  local distance = math.max(diff:length(), centralBody.radius)
  local direction = diff:normalise()
  local force = (satelliteBody.mass * centralBody.mass) / (distance ^ 1.9)

  return direction * force
end

function _M.updateSatellite(satellite, bodies, dt)
  local direction = satellite.velocity:normalise()

  local pull = b.vec2()
  for _, body in ipairs(bodies) do
    local gravity = getGravity(body, satellite)
    pull = pull + gravity
  end

  local newVelocity = satellite.velocity + direction * (satellite.thrust - satellite.friction) * dt + pull * dt
  local newPosition = satellite.position + satellite.velocity * dt

  if satellite.orbiting then
    local body = bodies[satellite.orbitingBody]
    local orbitVector = body.position - satellite.position
    local distance = orbitVector:length()

    if distance > satellite.radius + body.radius + body.orbit + 10 then
      satellite.orbiting = false
    else
      local orbitUnit = orbitVector:normalise()
      local approachAngle = orbitVector:angle_difference(satellite.velocity)
      local orbitAngle = orbitUnit:angle()
      local orbitSpeed = math.max(100, satellite.velocity:length())
      local orbitDireciton = approachAngle >= 0 and 1 or -1
      local surfaceDirection = orbitAngle + orbitDireciton * math.pi / 2
      local orbitingVelocity = b.vec2(math.cos(surfaceDirection), math.sin(surfaceDirection)) * orbitSpeed
      local orbitingPosition = satellite.position + orbitingVelocity * dt

      local orbitingDistance = (orbitingPosition - body.position):length()
      local normalDistance = (newPosition - body.position):length()

      if orbitingDistance > normalDistance then
        newVelocity = orbitingVelocity
        newPosition = orbitingPosition
      end
    end
  else
    for bodyIndex, body in ipairs(bodies) do
      local orbitVector = body.position - satellite.position
      local distance = orbitVector:length()

      if body.orbitable and distance <= satellite.radius + body.radius + body.orbit then
        satellite.orbiting = true
        satellite.orbitingBody = bodyIndex
        satellite.velocity = satellite.velocity * 0.8
        break
      end
    end
  end

  satellite.velocity = newVelocity
  satellite.position = newPosition
end

function _M.update(satellites, bodies, dt)
  for _, satellite in ipairs(satellites) do
    _M.updateSatellite(satellite, bodies, dt)
  end
end

return _M
