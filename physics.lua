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
  local direction = satellite.turnDirection

  local pull = b.vec2()
  for _, body in ipairs(bodies) do
    local gravity = getGravity(body, satellite)
    pull = pull + gravity
  end

  local thrustVector = direction * (satellite.thrust - satellite.friction) * dt
  if satellite.thrust - satellite.friction < 0 and thrustVector:length() > satellite.velocity:length() then
    thrustVector = -1 * satellite.velocity
  end
  local newVelocity = satellite.velocity + thrustVector + pull * dt
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
      local orbitDireciton = approachAngle >= 0 and 1 or -1
      local surfaceAngle = orbitAngle + orbitDireciton * math.pi / 2
      local surfaceDirection = b.vec2(math.cos(surfaceAngle), math.sin(surfaceAngle))
      local orbitSpeed
      if satellite.thrust > 0.1 then
        orbitSpeed = math.max(math.sqrt(body.mass / distance), satellite.velocity:length())
      else
        orbitSpeed = math.sqrt(body.mass / distance) - 10
      end
      local orbitingVelocity = surfaceDirection * orbitSpeed
      local orbitingPosition = satellite.position + orbitingVelocity * dt
      -- correction of orbiting position
      local correction = (orbitingPosition - body.position):length() - body.radius - body.orbit
      orbitingPosition = orbitingPosition:lerp(orbitingPosition + orbitUnit * correction, 0.2)

      local orbitingDistance = (orbitingPosition - body.position):length()
      local normalDistance = (newPosition - body.position):length()

      if orbitingDistance > normalDistance then
        newVelocity = newVelocity:lerp(orbitingVelocity, 0.2)
        newPosition = newPosition:lerp(orbitingPosition, 0.2)
      end
    end
  else
    for bodyIndex, body in ipairs(bodies) do
      local orbitVector = body.position - satellite.position
      local distance = orbitVector:length()

      if body.orbitable and distance <= satellite.radius + body.radius + body.orbit then
        satellite.orbiting = true
        satellite.orbitingBody = bodyIndex
        satellite.velocity = math.sqrt(body.mass / distance)
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
