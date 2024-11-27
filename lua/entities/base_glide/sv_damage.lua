function ENT:Repair()
    self:SetIsEngineOnFire( false )
    self:SetChassisHealth( self.MaxChassisHealth )
    self:SetEngineHealth( 1.0 )
    self:UpdateHealthOutputs()
end

function ENT:Explode( attacker )
    if self.hasExploded then return end

    -- Don't let stuff like collision/damage events
    -- call this again, to prevent infinite loops.
    self.hasExploded = true
    self:SetChassisHealth( 0 )

    attacker = attacker or self:GetDriver() or self:GetCreator() or self

    -- Damage blast & effects
    Glide.CreateExplosion( self, attacker, self:GetPos(), 500, 200, Vector( 0, 0, 1 ), Glide.EXPLOSION_TYPE.VEHICLE )

    -- Damage passengers
    for _, ply in ipairs( self:GetAllPlayers() ) do
        ply:TakeDamage( 999, attacker, self )
    end

    self:Remove()

    -- Spawn gibs
    local phys = self:GetPhysicsObject()

    if self.wheels and IsValid( phys ) then
        local vehPos = self:GetPos()

        for _, w in ipairs( self.wheels ) do
            if IsValid( w ) and not w:GetNoDraw() then
                local gibPos = w:GetPos()
                local gib = ents.Create( "glide_gib" )
                gib:SetPos( gibPos )
                gib:SetAngles( w:GetAngles() )
                gib:SetModel( w:GetModel() )
                gib:Spawn()
                gib:CopyVelocities( self )

                local gibPhys = gib:GetPhysicsObject()
                if IsValid( gibPhys ) then
                    local dir = gibPos - vehPos
                    dir:Normalize()
                    gibPhys:AddVelocity( dir * 300 )
                end
            end
        end
    end

    if #self.ExplosionGibs == 0 then
        local gib = ents.Create( "glide_gib" )
        gib:SetPos( self:GetPos() )
        gib:SetAngles( self:GetAngles() )
        gib:SetModel( self:GetModel() )
        gib:Spawn()
        gib:CopyVelocities( self )
        gib:SetOnFire()

        for _, v in ipairs( gib:GetBodyGroups() ) do
            gib:SetBodygroup( v.id, 1 )
        end

        return
    end

    for k, v in ipairs( self.ExplosionGibs ) do
        local gib = ents.Create( "glide_gib" )
        gib:SetPos( self:GetPos() )
        gib:SetAngles( self:GetAngles() )
        gib:SetModel( v )
        gib:Spawn()
        gib:CopyVelocities( self )

        if k == 1 then
            gib:SetOnFire()
        end
    end
end

function ENT:TakeEngineDamage( amount )
    self:SetEngineHealth( math.max( self:GetEngineHealth() - amount, 0 ) )
end

local IsValid = IsValid

local cvarBullet = GetConVar( "glide_damage_multiplier_bullet" )
local cvarBlast = GetConVar( "glide_damage_multiplier_blast" )

function ENT:OnTakeDamage( dmginfo )
    if self.hasExploded then return end

    local health = self:GetChassisHealth()
    local attacker = dmginfo:GetAttacker()
    local amount = dmginfo:GetDamage()

    if dmginfo:IsDamageType( 64 ) then -- DMG_BLAST
        amount = amount * self.BlastDamageMultiplier * cvarBlast:GetFloat()

        local phys = self:GetPhysicsObject()

        if IsValid( phys ) then
            local damagePos = dmginfo:GetDamagePosition()
            local damageForce = dmginfo:GetDamageForce() * phys:GetMass() * 0.01

            phys:ApplyForceOffset( damageForce, damagePos )
        end

    elseif dmginfo:IsDamageType( 2 ) then -- DMG_BULLET
        amount = amount * self.BulletDamageMultiplier * cvarBullet:GetFloat()
    end

    health = health - amount

    self:SetChassisHealth( health )
    self:TakeEngineDamage( amount * self.EngineDamageMultiplier )
    self:UpdateHealthOutputs()

    if health < 250 and self:WaterLevel() < 3 then
        self:SetIsEngineOnFire( true )
    end

    if health < 1 then
        self:Explode( attacker )
    end
end

local RealTime = RealTime
local DamageInfo = DamageInfo

local Abs = math.abs
local Clamp = math.Clamp
local RandomInt = math.random
local PlaySoundSet = Glide.PlaySoundSet

local cvarCollision = GetConVar( "glide_damage_multiplier_collision" )

function ENT:PhysicsCollide( data )
    local ent = data.HitEntity
    local normal = data.HitNormal

    local vel = data.OurOldVelocity - data.OurNewVelocity
    local speed = vel:Length()

    if speed < 30 then return end

    -- Ignore collision damage from missiles
    if IsValid( ent ) and ent:GetClass() == "glide_missile" then
        return
    end

    local isPlayer = IsValid( ent ) and ent:IsPlayer()

    if not isPlayer and speed > 300 then
        local dmg = DamageInfo()
        dmg:SetAttacker( ent )
        dmg:SetInflictor( self )
        dmg:SetDamage( ( speed / 8 ) * self.CollisionDamageMultiplier * cvarCollision:GetFloat() )
        dmg:SetDamageType( 1 ) -- DMG_CRUSH
        dmg:SetDamagePosition( data.HitPos )
        self:TakeDamageInfo( dmg )
    end

    local t = RealTime()

    if isPlayer then
        -- Don't let players make loud sounds
        speed = 100

    elseif t > self.collisionShakeCooldown then
        self.collisionShakeCooldown = t + 0.5
        Glide.SendViewPunch( self:GetAllPlayers(), Clamp( speed / 1500, 0, 1 ) * 3 )
    end

    if speed > 300 then
        local eff = EffectData()
        eff:SetOrigin( data.HitPos )
        eff:SetScale( math.min( speed * 0.01, 6 ) * self.CollisionParticleSize )
        eff:SetNormal( -data.HitSpeed:GetNormalized() )
        util.Effect( "glide_metal_impact", eff )
    end

    if speed > 300 then
        local veryHard = speed > 500

        PlaySoundSet( "Glide.Collision.VehicleSoft", self, speed / 300, nil, veryHard and 80 or 75 )
        PlaySoundSet( "Glide.Collision.VehicleHard", self, speed / 200, nil, veryHard and 80 or 75 )

        if veryHard and self.IsHeavyVehicle then
            self:EmitSound( "physics/metal/metal_barrel_impact_hard5.wav", 90, RandomInt( 70, 90 ), 1 )
        end

    elseif not isPlayer and Abs( normal:Dot( -data.HitSpeed:GetNormalized() ) ) < 0.2 then
        PlaySoundSet( "Glide.Collision.VehicleScrape", self, 0.4 )

    else
        if isPlayer then
            PlaySoundSet( "Glide.Collision.VehicleHard", ent, speed / 1000, RandomInt( 90, 130 ) )
        else
            PlaySoundSet( "Glide.Collision.VehicleHard", self, speed / 300, RandomInt( 90, 130 ) )
        end
    end

    if not self.FallOnCollision then return end

    -- Did the hit come from above the vehicle?
    if self:GetUp():Dot( data.HitNormal ) > 0.5 and self:WorldToLocal( data.HitPos )[3] > 0 then
        speed = speed + 600
    end

    if speed < 600 then return end

    if IsValid( ent ) then
        if ent:IsPlayer() or ent:IsNPC() then return end
        if ent:GetClass() == "func_breakable" then return end
    end

    vel = data.OurOldVelocity * 0.5
    vel[3] = vel[3] + 200

    -- Timer to avoid the "likely crashes the game" warning in console
    timer.Simple( 0, function()
        if IsValid( self ) then
            self:RagdollAllPlayers( 3, vel )
        end
    end )
end