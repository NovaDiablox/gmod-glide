local Camera = Glide.Camera or {}

Glide.Camera = Camera

hook.Add( "Glide_OnLocalEnterVehicle", "Glide.ActivateCamera", function( vehicle, seatIndex )
    Camera:Activate( vehicle, seatIndex )
end )

hook.Add( "Glide_OnLocalExitVehicle", "Glide.DeactivateCamera", function()
    Camera:Deactivate()
end )

Camera.aimPos = Vector()
Camera.viewAngles = Angle()
Camera.isInFirstPerson = false
Camera.FIRST_PERSON_DSP = 30

function Glide.GetCameraAimPos()
    return Camera.aimPos
end

local Config

function Camera:Activate( vehicle, seatIndex )
    Config = Glide.Config

    self.user = LocalPlayer()
    self.vehicle = vehicle
    self.seatIndex = seatIndex

    self.fov = 80
    self.origin = Vector()
    self.angles = vehicle:GetAngles()

    self.isActive = false
    self.isUsingDirectMouse = false
    self.allowRolling = false

    self.centerStrength = 0
    self.lastMouseMoveTime = 0
    self.traceFraction = 1

    self.punchAngle = Angle()
    self.punchVelocity = Angle()
    self.shakeOffset = Vector()

    self:SetFirstPerson( self.isInFirstPerson )

    hook.Add( "Think", "GlideCamera.Think", function()
        if self.isActive then return self:Think() end
    end )

    hook.Add( "CalcView", "GlideCamera.CalcView", function()
        if self.isActive then return self:CalcView() end
    end, HOOK_HIGH )

    hook.Add( "CreateMove", "GlideCamera.CreateMove", function( cmd )
        if self.isActive then return self:CreateMove( cmd ) end
    end, HOOK_HIGH )

    hook.Add( "InputMouseApply", "GlideCamera.InputMouseApply", function( _, x, y )
        if self.isActive then return self:InputMouseApply( x, y ) end
    end, HOOK_HIGH )

    hook.Add( "PlayerBindPress", "GlideCamera.PlayerBindPress", function( ply, bind )
        if ply == self.user and ( bind == "+right" or bind == "+left" ) then return false end
    end )

    timer.Create( "GlideCamera.CheckState", 0.2, 0, function()
        self.isActive = self:ShouldBeActive()

        local seat = self.user:GetVehicle()

        if IsValid( seat ) and not self.seat then
            self.seat = seat
            self.angles = seat:GetAngles() + Angle( 0, 90, 0 )
            self.angles[3] = 0
        end
    end )
end

function Camera:Deactivate()
    timer.Remove( "GlideCamera.CheckState" )

    hook.Remove( "Think", "GlideCamera.Think" )
    hook.Remove( "CalcView", "GlideCamera.CalcView" )
    hook.Remove( "CreateMove", "GlideCamera.CreateMove" )
    hook.Remove( "InputMouseApply", "GlideCamera.InputMouseApply" )
    hook.Remove( "PlayerBindPress", "GlideCamera.PlayerBindPress" )

    if IsValid( self.vehicle ) and self.vehicle.stream then
        self.vehicle.stream.firstPerson = false
    end

    if IsValid( self.user ) then
        self.user:SetDSP( 0 )
        self.user:SetEyeAngles( Angle() )
    end

    self.user = nil
    self.vehicle = nil
    self.seatIndex = nil
    self.seat = nil
end

function Camera:SetFirstPerson( enable )
    self.isInFirstPerson = enable
    self.centerStrength = 0
    self.lastMouseMoveTime = 0

    local muffleSound = self.isInFirstPerson

    if IsValid( self.vehicle ) then
        if self.vehicle.stream then
            self.vehicle.stream.firstPerson = enable
        end

        muffleSound = muffleSound and self.vehicle:AllowFirstPersonMuffledSound( self.seatIndex )
    end

    if IsValid( self.user ) then
        self.user:SetDSP( muffleSound and self.FIRST_PERSON_DSP or 0 )
    end
end

local IsValid = IsValid

function Camera:ShouldBeActive()
    if not IsValid( self.vehicle ) then
        return false
    end

    if not self.user:Alive() then
        return false
    end

    if self.user:GetViewEntity() ~= self.user then
        return false
    end

    if pace and pace.Active then
        return false
    end

    return true
end

local Abs = math.abs

function Camera:ViewPunch( pitch, yaw, roll )
    if not self.isActive then return end

    pitch = self.isInFirstPerson and pitch * 2 or pitch
    if Abs( pitch ) < Abs( self.punchVelocity[1] ) then return end

    self.punchVelocity[1] = pitch
    self.punchVelocity[2] = yaw or 0
    self.punchVelocity[3] = roll or 0

    self.punchAngle[1] = 0
    self.punchAngle[2] = 0
    self.punchAngle[3] = 0
end

local RealTime = RealTime
local FrameTime = FrameTime

local Cos = math.cos
local Clamp = math.Clamp
local IsKeyDown = input.IsKeyDown

local ExpDecay = Glide.ExpDecay
local ExpDecayAngle = Glide.ExpDecayAngle

local CAMERA_TYPE = Glide.CAMERA_TYPE
local MOUSE_FLY_MODE = Glide.MOUSE_FLY_MODE

function Camera:Think()
    local vehicle = self.vehicle

    if not IsValid( vehicle ) then
        self:Deactivate()
        return
    end

    -- Toggle first person
    local isSwitchKeyDown = IsKeyDown( KEY_LCONTROL ) and not vgui.CursorVisible()

    if self.isSwitchKeyDown ~= isSwitchKeyDown then
        self.isSwitchKeyDown = isSwitchKeyDown

        if isSwitchKeyDown then
            self:SetFirstPerson( not self.isInFirstPerson )
        end
    end

    local t = RealTime()
    local dt = FrameTime()

    local angles = self.angles
    local vehicleAngles = vehicle:GetAngles()
    local velocity = vehicle:GetVelocity()
    local speed = Abs( velocity:Length() )
    local mode = vehicle:OverrideCameraType( self.seatIndex ) or vehicle.CameraType or CAMERA_TYPE.CAR

    self.mode = mode

    local decay, rollDecay = 3, 3

    if mode == CAMERA_TYPE.TURRET then
        self.centerStrength = 0
        self.allowRolling = false
        decay = 0

    elseif mode == CAMERA_TYPE.AIRCRAFT then
        self.isUsingDirectMouse = Config.mouseFlyMode == MOUSE_FLY_MODE.DIRECT and self.seatIndex == 1 and not IsKeyDown( Config.binds.free_look )
        self.allowRolling = Config.mouseFlyMode ~= MOUSE_FLY_MODE.AIM

        -- Make the camera angles smoothly point towards the vehicle's forward direction.
        decay = ( self.isUsingDirectMouse or self.isInFirstPerson ) and 6 or Clamp( ( speed - 5 ) * 0.01, 0, 1 ) * 3
        decay = decay * self.centerStrength

    else
        self.isUsingDirectMouse = false

        if self.isInFirstPerson then
            self.allowRolling = true

            decay = Clamp( ( speed - 5 ) * 0.002, 0, 1 ) * 7 * self.centerStrength
            rollDecay = 8
        else
            self.allowRolling = false

            vehicleAngles = velocity:Angle()
            vehicleAngles[3] = 0
            decay = Clamp( ( speed - 10 ) * 0.002, 0, 1 ) * 3 * self.centerStrength
        end
    end

    if self.allowRolling then
        -- Roll the camera so it stays "upright" relative to the vehicle
        vehicleAngles[3] = vehicleAngles[3] * vehicle:GetForward():Dot( angles:Forward() )
    end

    angles[1] = ExpDecayAngle( angles[1], vehicleAngles[1], decay, dt )
    angles[2] = ExpDecayAngle( angles[2], vehicleAngles[2], decay, dt )
    angles[3] = ExpDecayAngle( angles[3], self.allowRolling and vehicleAngles[3] or 0, rollDecay, dt )

    -- Recenter if using "Control movement directly" mouse setting,
    -- or if some time has passed since last time we moved the mouse.
    if
        self.isUsingDirectMouse or (
            Config.enableAutoCenter and
            mode ~= CAMERA_TYPE.TURRET and
            t > self.lastMouseMoveTime + Config.autoCenterDelay and
            ( Config.mouseFlyMode ~= MOUSE_FLY_MODE.AIM or mode == CAMERA_TYPE.CAR or self.seatIndex > 1 )
        )
    then
        self.centerStrength = ExpDecay( self.centerStrength, 1, 2, dt )
    end

    -- Update offset from movement
    velocity = vehicle:WorldToLocal( vehicle:GetPos() + velocity )

    -- Update view punch
    do
        local vel, ang = self.punchVelocity, self.punchAngle

        ang[1] = ExpDecay( ang[1], 0, 6, dt ) + vel[1]
        ang[2] = ExpDecay( ang[2], 0, 6, dt ) + vel[2]

        decay = self.isInFirstPerson and 8 or 10
        vel[1] = ExpDecay( vel[1], 0, decay, dt )
        vel[2] = ExpDecay( vel[2], 0, decay, dt )
    end

    -- Update FOV depending on speed
    speed = speed - 400

    local fov = ( self.isInFirstPerson and Config.cameraFOVInternal or Config.cameraFOVExternal ) + Clamp( speed * 0.01, 0, 15 )
    local keyZoom = self.user:KeyDown( IN_ZOOM )

    self.fov = ExpDecay( self.fov, keyZoom and 20 or fov, keyZoom and 5 or 2, dt )

    -- Apply a small shake
    if mode == CAMERA_TYPE.CAR then
        local mult = Clamp( speed * 0.001, 0, 1 )

        self.shakeOffset[2] = Cos( t * 1.5 ) * 4 * mult
        self.shakeOffset[3] = ( ( Cos( t * 2 ) * 1.8 ) + ( Cos( t * 30 ) * 0.4 ) ) * mult
    end

    self.traceFraction = ExpDecay( self.traceFraction, 1, 2, dt )
end

local TraceLine = util.TraceLine

function Camera:CalcView()
    local vehicle = self.vehicle
    if not IsValid( vehicle ) then return end

    local user = self.user
    local angles = self.angles

    if self.isInFirstPerson then
        local localEyePos = vehicle:WorldToLocal( user:EyePos() )
        self.origin = vehicle:LocalToWorld( localEyePos + vehicle.CameraFirstPersonOffset )
    else
        local fraction = self.traceFraction
        local offset = self.shakeOffset + vehicle.CameraOffset * Vector( Config.cameraDistance, 1, Config.cameraHeight ) * fraction
        local startPos = vehicle:GetPos()

        angles = angles + vehicle.CameraAngleOffset

        local endPos = startPos
            + angles:Forward() * offset[1]
            + angles:Right() * offset[2]
            + angles:Up() * offset[3]

        local dir = endPos - startPos
        dir:Normalize()

        -- Make sure the camera stays outside of walls
        local tr = TraceLine( {
            start = startPos,
            endpos = endPos + dir * 10,
            mask = 16395 -- MASK_SOLID_BRUSHONLY
        } )

        if tr.Hit then
            endPos = tr.HitPos - dir * 10

            if tr.Fraction < fraction then
                self.traceFraction = tr.Fraction
            end
        end

        self.origin = endPos
    end

    local dir

    if Config.mouseFlyMode == MOUSE_FLY_MODE.AIM and self.mode == CAMERA_TYPE.AIRCRAFT then
        -- Make the player's view angles point
        -- in the same direction as the camera.
        dir = angles:Forward()
    else
        -- Make the player's view angles point
        -- towards where the camera is pointing at.
        local tr = TraceLine( {
            start = self.origin,
            endpos = self.origin + angles:Forward() * 10000,
            filter = { user, vehicle }
        } )

        dir = tr.HitPos - user:EyePos()
        dir:Normalize()

        self.aimPos = tr.HitPos
    end

    if IsValid( self.seat ) then
        -- Make the view angles relative to the seat
        self.viewAngles = self.seat:WorldToLocalAngles( dir:Angle() )
    else
        self.viewAngles = dir:Angle()
    end

    return {
        origin = self.origin,
        angles = angles + self.punchAngle,
        fov = self.fov,
        drawviewer = not self.isInFirstPerson
    }
end

function Camera:CreateMove( cmd )
    -- Use the angles from the camera trace
    cmd:SetViewAngles( self.viewAngles )
end

function Camera:InputMouseApply( x, y )
    local vehicle = self.vehicle
    if not IsValid( vehicle ) then return end
    if self.isUsingDirectMouse then return end

    local sensitivity = Config.lookSensitivity
    local lookX = ( Config.cameraInvertX and -x or x ) * 0.05 * sensitivity
    local lookY = ( Config.cameraInvertY and -y or y ) * 0.05 * sensitivity

    if Abs( lookX ) + Abs( lookY ) > 0.1 then
        self.lastMouseMoveTime = RealTime()
        self.centerStrength = 0
    end

    local angles = self.allowRolling and vehicle:WorldToLocalAngles( self.angles ) or self.angles

    angles[1] = Clamp( angles[1] + lookY, -80, 60 )
    angles[2] = ( angles[2] - lookX ) % 360

    self.angles = self.allowRolling and vehicle:LocalToWorldAngles( angles ) or angles
end