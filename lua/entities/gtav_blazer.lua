AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_glide_car"
ENT.PrintName = "Blazer"

ENT.GlideCategory = "Default"
ENT.ChassisModel = "models/gta5/vehicles/blazer/chassis.mdl"
ENT.SeatDriverAnim = "drive_airboat" -- sit, sit_rollercoaster

DEFINE_BASECLASS( "base_glide_car" )

if CLIENT then
    ENT.CameraOffset = Vector( -170, 0, 43 )
    ENT.CameraFirstPersonOffset = Vector( 0, 0, 0 )

    ENT.ExhaustOffsets = {
        { pos = Vector( -39, 10, 11 ), scale = 0.7 }
    }

    ENT.EngineSmokeStrips = {
        { offset = Vector( 5, 0, -5 ), angle = Angle( 40, 180, 0 ), width = 15 }
    }

    ENT.EngineFireOffsets = {
        { offset = Vector( -3, 5, -5 ), angle = Angle( 90, 90, 0 ), scale = 0.4 },
        { offset = Vector( -3, -5, -5 ), angle = Angle( 90, 270, 0 ), scale = 0.4 }
    }

    ENT.LightSprites = {
        { type = "brake", offset = Vector( -33, 0, 9 ), dir = Vector( -1, 0, 0 ), lightRadius = 50 },
        { type = "headlight", offset = Vector( 20, 0, 9 ), dir = Vector( 1, 0, 0 ), color = Glide.DEFAULT_HEADLIGHT_COLOR }
    }

    ENT.Headlights = {
        { offset = Vector( 19, 0, 18 ), color = Glide.DEFAULT_HEADLIGHT_COLOR }
    }

    ENT.StartSound = "Glide.Engine.BikeStart1"
    ENT.HornSound = "glide/horns/car_horn_light_1.wav"
    ENT.ExternalGearSwitchSound = ""
    ENT.InternalGearSwitchSound = ""

    function ENT:AllowWindSound()
        return true, 1
    end

    function ENT:OnCreateEngineStream( stream )
        stream.offset = Vector( 5, 0, 0 )
        stream:LoadPreset( "sanchez" )
    end

    local POSE_DATA = {
        ["ValveBiped.Bip01_L_UpperArm"] = Angle( -3, 5, 0 ),
        ["ValveBiped.Bip01_R_UpperArm"] = Angle( 6, 8, -5 ),
        ["ValveBiped.Bip01_L_Thigh"] = Angle( 0, -15, 0 ),
        ["ValveBiped.Bip01_L_Calf"] = Angle( -20, 80, 0 ),
        ["ValveBiped.Bip01_R_Thigh"] = Angle( 0, -15, 0 ),
        ["ValveBiped.Bip01_R_Calf"] = Angle( 20, 80, 0 )
    }

    --- Override the base class `GetSeatBoneManipulations` function.
    function ENT:GetSeatBoneManipulations()
        return POSE_DATA
    end

    --- Override the base class `AllowFirstPersonMuffledSound` function.
    function ENT:AllowFirstPersonMuffledSound()
        return false
    end

    --- Override the base class `OnActivateMisc` function.
    function ENT:OnActivateMisc()
        BaseClass.OnActivateMisc( self )

        self.handlebarsBoneId = self:LookupBone( "handlebars" )
        self.boneGear = self:LookupBone( "misc_a" )
        self.boneTransmission = self:LookupBone( "transmission" )
        self.boneSuspensionFL = self:LookupBone( "suspension_fl" )
        self.boneSuspensionFR = self:LookupBone( "suspension_fr" )
        self.boneSpringR = self:LookupBone( "spring_rear" )
    end

    local Abs = math.abs
    local Clamp = math.Clamp

    local IsValid = IsValid
    local steerAngle = Angle()
    local tempAngle = Angle()

    local BAR_OFFSET_DOWN = Vector( 2, 0, -6 )
    local BAR_OFFSET_UP = Vector( -1, 0, 9 )

    --- Override the base class `OnUpdateAnimations` function.
    function ENT:OnUpdateAnimations()
        if not self.handlebarsBoneId then return end

        steerAngle[1] = self:GetSteering() * -28
        self:ManipulateBoneAngles( self.handlebarsBoneId, steerAngle )

        local wheels = self.wheels
        if not wheels then return end

        local rl = wheels[3]
        local rr = wheels[4]
        if not IsValid( rl ) or not IsValid( rr ) then return end

        -- Spin the gear bone
        tempAngle[2] = 0
        tempAngle[3] = -rl:GetSpin()
        self:ManipulateBoneAngles( self.boneGear, tempAngle )

        -- Rotate and move the rear transmission bar
        local offset = Clamp( Abs( rl:GetLocalPos()[3] + rr:GetLocalPos()[3] ) / 30, 0, 1 )
        local invOffset = 1 - offset

        tempAngle[3] = -18 + invOffset * 44
        self:ManipulateBoneAngles( self.boneTransmission, tempAngle )
        self:ManipulateBonePosition( self.boneGear, ( BAR_OFFSET_DOWN * offset ) + ( BAR_OFFSET_UP * invOffset ) )

        -- Rotate ans scale rear spring
        tempAngle[3] = 10 - offset * 20
        self:ManipulateBoneAngles( self.boneSpringR, tempAngle )
        self:ManipulateBoneScale( self.boneSpringR, Vector( 1, 0.5 + offset, 1 ) )
        self:ManipulateBonePosition( self.boneSpringR, Vector( 0, 0, 1.5 + offset * -3 ) )

        local fl = wheels[1]
        local fr = wheels[2]
        if not IsValid( fl ) or not IsValid( fr ) then return end

        -- Reposition the front springs
        tempAngle[3] = 0

        offset = Clamp( Abs( fl:GetLocalPos()[3] ) / 15, 0, 1 )
        tempAngle[2] = 30 - offset * 50
        self:ManipulateBoneAngles( self.boneSuspensionFL, tempAngle )

        offset = Clamp( Abs( fr:GetLocalPos()[3] ) / 15, 0, 1 )
        tempAngle[2] = -30 + offset * 50
        self:ManipulateBoneAngles( self.boneSuspensionFR, tempAngle )
    end
end

if SERVER then
    duplicator.RegisterEntityClass( "gtav_blazer", Glide.VehicleFactory, "Data" )

    ENT.ChassisMass = 400
    ENT.FallOnCollision = true
    ENT.SpawnPositionOffset = Vector( 0, 0, 40 )

    ENT.SuspensionHeavySound = "Glide.Suspension.CompressBike"
    ENT.SteerSpeedFactor = 1200
    ENT.StartupTime = 0.4

    ENT.BurnoutForce = 130

    ENT.AirControlForce = Vector( 3, 2, 0.2 ) -- Roll, pitch, yaw
    ENT.AirMaxAngularVelocity = Vector( 400, 400, 150 ) -- Roll, pitch, yaw

    function ENT:GetGears()
        return {
            [-1] = 3.0, -- Reverse
            [0] = 0, -- Neutral (this number has no effect)
            [1] = 3.0,
            [2] = 1.78,
            [3] = 1.2,
            [4] = 0.9,
            [5] = 0.78
        }
    end

    ENT.LightBodygroups = {
        { type = "headlight", bodyGroupId = 3, subModelId = 1 }, -- Headlight
        { type = "headlight", bodyGroupId = 2, subModelId = 1 } -- Tail light
    }

    function ENT:CreateFeatures()
        self:SetTransmissionEfficiency( 0.7 )
        self:SetDifferentialRatio( 1.2 )
        self:SetBrakePower( 1300 )
        self:SetWheelInertia( 6 )

        self:SetMaxRPM( 15000 )
        self:SetMinRPMTorque( 980 )
        self:SetMaxRPMTorque( 1000 )

        self:SetSuspensionLength( 10 )
        self:SetSpringStrength( 450 )
        self:SetSpringDamper( 2800 )

        self:CreateSeat( Vector( -23, 0, 4 ), Angle( 0, 270, -16 ), Vector( 0, 60, 0 ), true )

        -- Front left
        self:CreateWheel( Vector( 25, 18, -5 ), {
            model = "models/gta5/vehicles/blazer/wheel.mdl",
            modelScale = Vector( 0.5, 1, 1 ),
            modelAngle = Angle( 0, 90, 0 ),
            steerMultiplier = 1,
            enableAxleForces = true
        } )

        -- Front right
        self:CreateWheel( Vector( 25, -18, -5 ), {
            model = "models/gta5/vehicles/blazer/wheel.mdl",
            modelAngle = Angle( 0, -90, 0 ),
            modelScale = Vector( 0.5, 1, 1 ),
            steerMultiplier = 1,
            enableAxleForces = true
        } )

        -- Rear left
        self:CreateWheel( Vector( -27, 18, -5 ), {
            model = "models/gta5/vehicles/blazer/wheel.mdl",
            modelScale = Vector( 0.5, 1, 1 ),
            modelAngle = Angle( 0, 90, 0 ),
            isPowered = true,
            enableAxleForces = true
        } )

        -- Rear right
        self:CreateWheel( Vector( -27, -18, -5 ), {
            model = "models/gta5/vehicles/blazer/wheel.mdl",
            modelAngle = Angle( 0, -90, 0 ),
            modelScale = Vector( 0.5, 1, 1 ),
            isPowered = true,
            enableAxleForces = true
        } )

        self:ChangeWheelRadius( 11 )
    end
end
