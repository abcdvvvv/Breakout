using GLMakie, GeometryBasics
using LinearAlgebra, Random, Printf

const P2 = Point2f
const V2 = Vec2f
const Rect2 = GeometryBasics.Rect{2,Float32}

const COLOR_BG = RGBAf(0.18, 0.20, 0.25, 1.0)
const COLOR_TEXT = RGBAf(0.90, 0.93, 0.97, 1.0)
const COLOR_PADDLE = RGBAf(0.53, 0.75, 0.82, 1.0)
const COLOR_BALL = RGBAf(0.93, 0.94, 0.96, 1.0)
const COLOR_BRICK1 = RGBAf(0.51, 0.63, 0.76, 1.0)
const COLOR_BRICK2 = RGBAf(0.75, 0.38, 0.42, 1.0)
const COLOR_BRICK3 = RGBAf(0.92, 0.80, 0.55, 1.0)
const COLOR_HUDBG = RGBAf(0.0, 0.0, 0.0, 0.35)
const COLOR_PU_PIERCE = RGBAf(0.98, 0.74, 0.26, 1.0)
const COLOR_PU_MULTIBALL = RGBAf(0.45, 0.80, 0.75, 1.0)
const COLOR_PU_LASER = RGBAf(0.94, 0.48, 0.35, 1.0)
const COLOR_LASER_SHOT = RGBAf(0.99, 0.86, 0.40, 1.0)
const HINT_FONT_SIZE = 26
const HINT_LINE_HEIGHT = 2.0f0

@enum PowerupKind Pierce Multiball Laser

@kwdef struct WorldConfig
    width::Float32 = 1200f0
    height::Float32 = 900f0
    fixed_dt::Float32 = 1f0 / 300f0
end

@kwdef struct PaddleConfig
    width_at_800::Float32 = 100f0
    height_at_800::Float32 = 14f0
    y_at_600::Float32 = 40f0
    speed_at_800::Float32 = 480f0
end

@kwdef struct BallConfig
    radius_at_800::Float32 = 8f0
    initial_velocity_at_800::Vec2f = V2(176f0, 264f0)
    max_speed::Float32 = 600f0
    level_speed_growth::Float32 = 1.1f0
    min_bounce_degrees::Float32 = 25f0
    max_bounce_degrees::Float32 = 70f0
    trail_length::Int = 12
end

@kwdef struct LevelConfig
    cols::Int = 12
    rows::Int = 7
    margin::Float32 = 36f0
    gutter::Float32 = 12f0
    field_height_fraction::Float32 = 0.50f0
    hud_gap::Float32 = 48f0
    manual_min::Int = 1
    manual_max::Int = 5
    min_bricks::Int = 14
    random_hole_probability::Float32 = 0.06f0
end

@kwdef struct PowerupConfig
    drop_probability::Float32 = 0.16f0
    drops_per_level::Int = 10
    pierce_duration::Float32 = 6f0
    laser_duration::Float32 = 10f0
    shot_cooldown::Float32 = 0.7f0
    shot_speed::Float32 = 700f0
    shot_ttl::Float32 = 1.2f0
    shot_hit_radius_at_800::Float32 = 3f0
    multiball_count::Int = 2
    multiball_arc_radians::Float32 = 0.50f0
    child_ttl::Float32 = Inf32
    item_start_speed::Float32 = -40f0
    item_gravity::Float32 = 220f0
    item_damping::Float32 = 0.995f0
    item_marker_size_at_800::Float32 = 14f0
    item_pickup_radius_factor::Float32 = 0.67f0
    weights::NTuple{3,Float32} = (0.40f0, 0.35f0, 0.25f0)
end

@kwdef struct FxConfig
    flash_duration::Float32 = 0.18f0
    damaged_particles::Int = 12
    destroyed_particles::Int = 28
    damaged_ttl_range::Tuple{Float32,Float32} = (0.25f0, 0.50f0)
    destroyed_ttl_range::Tuple{Float32,Float32} = (0.45f0, 0.80f0)
    damaged_speed_range_at_800::Tuple{Float32,Float32} = (90f0, 210f0)
    destroyed_speed_range_at_800::Tuple{Float32,Float32} = (120f0, 280f0)
    particle_gravity::Float32 = 200f0
    particle_damping::Float32 = 0.99f0
end

@kwdef struct ScoreConfig
    damaged_brick::Int = 50
    destroyed_brick::Int = 100
    combo_step::Float32 = 0.1f0
    combo_cap::Int = 10
end

@kwdef struct GameConfig
    world::WorldConfig = WorldConfig()
    paddle::PaddleConfig = PaddleConfig()
    ball::BallConfig = BallConfig()
    level::LevelConfig = LevelConfig()
    powerup::PowerupConfig = PowerupConfig()
    fx::FxConfig = FxConfig()
    score::ScoreConfig = ScoreConfig()
    starting_lives::Int = 3
end

mutable struct Paddle
    x::Float32
    y::Float32
    w::Float32
    h::Float32
    speed::Float32
end

mutable struct Ball
    pos::Point2f
    vel::Vec2f
    ttl::Float32
end

mutable struct BallState
    main::Ball
    extras::Vector{Ball}
    launched::Bool
    trail::Vector{Point2f}
end

mutable struct Brick
    rect::Rect2
    hp::Int
    color::RGBAf
    flash::Float32
end

mutable struct LevelState
    index::Int
    bricks::Vector{Brick}
end

mutable struct PowerupItem
    pos::Point2f
    vel::Vec2f
    kind::PowerupKind
end

mutable struct LaserShot
    pos::Point2f
    vel::Vec2f
    ttl::Float32
end

mutable struct PowerupState
    items::Vector{PowerupItem}
    shots::Vector{LaserShot}
    pierce_ttl::Float32
    laser_ttl::Float32
    next_shot::Float32
    drops_left::Int
end

mutable struct Particle
    pos::Point2f
    vel::Vec2f
    ttl::Float32
    ttl_max::Float32
    color::RGBAf
end

mutable struct FxState
    particles::Vector{Particle}
end

mutable struct ComboState
    count::Int
end

mutable struct Game
    cfg::GameConfig
    rng::MersenneTwister
    paddle::Paddle
    balls::BallState
    level::LevelState
    powerups::PowerupState
    fx::FxState
    combo::ComboState
    score::Int
    lives::Int
    paused::Bool
end

mutable struct View
    bricks::Observable{Vector{Rect2}}
    brick_colors::Observable{Vector{RGBAf}}
    paddle::Observable{Rect2}
    balls::Observable{Vector{Point2f}}
    ball_colors::Observable{Vector{RGBAf}}
    trail_points::Observable{Vector{Point2f}}
    trail_colors::Observable{Vector{RGBAf}}
    items::Observable{Vector{Point2f}}
    item_colors::Observable{Vector{RGBAf}}
    shots::Observable{Vector{Point2f}}
    particles::Observable{Vector{Point2f}}
    particle_colors::Observable{Vector{RGBAf}}
    score_text::Observable{String}
    lives_text::Observable{String}
    level_text::Observable{String}
    pierce_text::Observable{String}
    laser_text::Observable{String}
    combo_text::Observable{String}
    combo_color::Observable{RGBAf}
    hint_bg::Observable{Vector{Rect2}}
    hint_text::Observable{String}
end

scale_x(cfg::GameConfig) = cfg.world.width / 800f0
scale_y(cfg::GameConfig) = cfg.world.height / 600f0
rectf(x::Real, y::Real, w::Real, h::Real) = Rect2(P2(Float32(x), Float32(y)), V2(Float32(w), Float32(h)))
rect_bounds(r::Rect2) = (r.origin[1], r.origin[2], r.origin[1] + r.widths[1], r.origin[2] + r.widths[2])
hp_color(hp::Int) = hp <= 1 ? COLOR_BRICK1 : (hp == 2 ? COLOR_BRICK2 : COLOR_BRICK3)
powerup_color(kind::PowerupKind) = kind == Pierce ? COLOR_PU_PIERCE : (kind == Multiball ? COLOR_PU_MULTIBALL : COLOR_PU_LASER)

@inline function mix_rgba(a::RGBAf, b::RGBAf, t::Float32)
    u = clamp(t, 0f0, 1f0)
    return RGBAf(
        a.r + (b.r - a.r) * u,
        a.g + (b.g - a.g) * u,
        a.b + (b.b - a.b) * u,
        a.alpha + (b.alpha - a.alpha) * u,
    )
end

function ball_radius(cfg::GameConfig)
    return cfg.ball.radius_at_800 * scale_x(cfg)
end

function initial_ball_velocity(cfg::GameConfig, level::Int)
    level_factor = cfg.ball.level_speed_growth ^ max(level - 1, 0)
    return cfg.ball.initial_velocity_at_800 * scale_x(cfg) * level_factor
end

function paddle_from_config(cfg::GameConfig)
    sx, sy = scale_x(cfg), scale_y(cfg)
    w = cfg.paddle.width_at_800 * sx
    h = cfg.paddle.height_at_800 * sx
    y = cfg.paddle.y_at_600 * sy
    return Paddle(cfg.world.width / 2 - w / 2, y, w, h, cfg.paddle.speed_at_800 * sx)
end

function make_level(rng::AbstractRNG, cfg::GameConfig, level::Int)
    lc = cfg.level
    cols, rows = lc.cols, lc.rows
    totalw = cfg.world.width - 2f0 * lc.margin
    bw = (totalw - (cols - 1) * lc.gutter) / cols
    area_h = cfg.world.height * lc.field_height_fraction
    bh = (area_h - (Float32(rows) - 1f0) * lc.gutter) / Float32(rows)
    y_top = cfg.world.height - lc.hud_gap
    y0 = y_top - bh - (rows - 1f0) * (bh + lc.gutter)

    bricks = Brick[]
    center_col = (cols + 1) / 2
    center_row = (rows + 1) / 2
    pattern = rand(rng, 1:6)
    offset = rand(rng, 0:1)
    period = rand(rng, 3:4)
    width = rand(rng, 1:2)
    amplitude = Float32(rand(rng, 1:2))
    frequency = rand(rng, 1:2)
    phase = rand(rng, Float32) * 2f0 * Float32(pi)
    thickness = rand(rng, 1:2)
    radius = rand(rng, 2:3)
    centers = [(rand(rng, 1:cols), rand(rng, 2:rows)) for _ in 1:rand(rng, 2:3)]

    for row in 1:rows, col in 1:cols
        keep = false
        hp = 1
        if level <= 1
            keep = isodd(col + row)
        elseif pattern == 1
            keep = isodd(col + row + offset) || (abs(col - center_col) <= 1 && isodd(row + offset))
            hp = row <= center_row ? 1 : 2
        elseif pattern == 2
            keep = ((col + offset) % period) < width
            hp = row >= rows - 2 ? 2 : 1
        elseif pattern == 3
            yline = center_row + amplitude * sin(phase + (2f0 * Float32(pi) * frequency) * ((col - 1f0) / cols))
            keep = abs(row - yline) <= thickness
            hp = abs(row - center_row) <= 1 ? 2 : 1
        elseif pattern == 4
            keep = (abs(col - center_col) + abs(row - center_row)) <= (radius + (isodd(col + row) ? 1 : 0))
            hp = row < center_row ? 1 : (row > center_row ? 3 : 2)
        elseif pattern == 5
            border = col == 1 || col == cols || row == 1 || row == rows
            diag = abs(col - row) <= 1 || abs((cols - col + 1) - row) <= 1
            keep = border || (diag && isodd(col + row + offset))
            hp = border ? 2 : 1
        else
            keep = any(abs(col - cx) + abs(row - cy) <= radius for (cx, cy) in centers) && rand(rng, Float32) < 0.85f0
            hp = abs(row - center_row) <= 1 ? 2 : 1
        end

        keep && rand(rng, Float32) < lc.random_hole_probability && (keep = false)
        if keep
            x = lc.margin + (col - 1f0) * (bw + lc.gutter)
            y = y0 + (row - 1f0) * (bh + lc.gutter)
            push!(bricks, Brick(rectf(x, y, bw, bh), hp, hp_color(hp), 0f0))
        end
    end

    if length(bricks) < lc.min_bricks
        empty!(bricks)
        for row in 1:rows, col in 1:cols
            if ((col + offset) % 3) < 2
                x = lc.margin + (col - 1f0) * (bw + lc.gutter)
                y = y0 + (row - 1f0) * (bh + lc.gutter)
                hp = row >= rows - 2 ? 2 : 1
                push!(bricks, Brick(rectf(x, y, bw, bh), hp, hp_color(hp), 0f0))
            end
        end
    end
    return LevelState(level, bricks)
end

function new_game(cfg::GameConfig=GameConfig())
    rng = MersenneTwister(rand(UInt))
    paddle = paddle_from_config(cfg)
    level = make_level(rng, cfg, 1)
    ball = Ball(P2(0f0, 0f0), initial_ball_velocity(cfg, 1), Inf32)
    balls = BallState(ball, Ball[], false, Point2f[])
    powerups = PowerupState(PowerupItem[], LaserShot[], 0f0, 0f0, 0f0, cfg.powerup.drops_per_level)
    game = Game(cfg, rng, paddle, balls, level, powerups, FxState(Particle[]), ComboState(0), 0, cfg.starting_lives, false)
    reset_ball!(game)
    return game
end

function reset_ball!(game::Game)
    r = ball_radius(game.cfg)
    game.balls.main.pos = P2(game.paddle.x + game.paddle.w / 2, game.paddle.y + game.paddle.h + r + 1f0)
    game.balls.main.vel = initial_ball_velocity(game.cfg, game.level.index)
    game.balls.main.ttl = Inf32
    game.balls.launched = false
    empty!(game.balls.trail)
    nothing
end

function reset_combo!(game::Game)
    game.combo.count = 0
    nothing
end

function reset_fx!(game::Game)
    empty!(game.fx.particles)
    for brick in game.level.bricks
        brick.flash = 0f0
    end
    nothing
end

function reset_powerups!(game::Game)
    empty!(game.powerups.items)
    empty!(game.powerups.shots)
    game.powerups.pierce_ttl = 0f0
    game.powerups.laser_ttl = 0f0
    game.powerups.next_shot = 0f0
    game.powerups.drops_left = game.cfg.powerup.drops_per_level
    empty!(game.balls.extras)
    nothing
end

function set_level!(game::Game, level::Int)
    clamped = clamp(level, game.cfg.level.manual_min, game.cfg.level.manual_max)
    game.level = make_level(game.rng, game.cfg, clamped)
    reset_fx!(game)
    reset_powerups!(game)
    reset_combo!(game)
    reset_ball!(game)
    nothing
end

function reset_run!(game::Game)
    game.score = 0
    game.lives = game.cfg.starting_lives
    game.level = make_level(game.rng, game.cfg, 1)
    reset_fx!(game)
    reset_powerups!(game)
    reset_combo!(game)
    reset_ball!(game)
    nothing
end

function lose_life!(game::Game)
    game.lives -= 1
    game.lives <= 0 ? reset_run!(game) : (reset_powerups!(game); reset_combo!(game); reset_ball!(game))
    nothing
end

function circle_rect_overlap(c::Point2f, radius::Float32, rect::Rect2)
    x1, y1, x2, y2 = rect_bounds(rect)
    nearest = P2(clamp(c[1], x1, x2), clamp(c[2], y1, y2))
    delta = c - nearest
    return dot(delta, delta) <= radius * radius
end

function collision_normal(prev::Point2f, pos::Point2f, radius::Float32, rect::Rect2)
    x1, y1, x2, y2 = rect_bounds(rect)
    penetration = (
        ((pos[1] + radius) - x1, V2(-1f0, 0f0)),
        (x2 - (pos[1] - radius), V2(1f0, 0f0)),
        ((pos[2] + radius) - y1, V2(0f0, -1f0)),
        (y2 - (pos[2] - radius), V2(0f0, 1f0)),
    )
    _, normal = findmin(first, penetration)
    n = penetration[normal][2]
    if n[1] != 0
        return prev[1] <= x1 ? V2(-1f0, 0f0) : (prev[1] >= x2 ? V2(1f0, 0f0) : n)
    end
    return prev[2] <= y1 ? V2(0f0, -1f0) : (prev[2] >= y2 ? V2(0f0, 1f0) : n)
end

function clamp_speed(v::Vec2f, max_speed::Float32)
    speed = norm(v)
    return speed > max_speed ? v * (max_speed / speed) : v
end

function rotate_velocity(v::Vec2f, angle::Float32)
    c, s = cos(angle), sin(angle)
    return V2(v[1] * c - v[2] * s, v[1] * s + v[2] * c)
end

function add_particles!(game::Game, center::Point2f, color::RGBAf, count::Int, speed_range, ttl_range)
    sx = scale_x(game.cfg)
    min_speed, max_speed = speed_range
    min_ttl, max_ttl = ttl_range
    for _ in 1:count
        angle = 2f0 * Float32(pi) * rand(game.rng, Float32)
        speed = (min_speed + rand(game.rng, Float32) * (max_speed - min_speed)) * sx
        ttl = min_ttl + rand(game.rng, Float32) * (max_ttl - min_ttl)
        push!(game.fx.particles, Particle(center, V2(cos(angle) * speed, sin(angle) * speed), ttl, ttl, color))
    end
    nothing
end

function score_multiplier(game::Game)
    c = game.cfg.score
    return 1f0 + c.combo_step * clamp(game.combo.count - 1, 0, c.combo_cap)
end

function sample_powerup(game::Game)
    weights = game.cfg.powerup.weights
    roll = rand(game.rng, Float32) * sum(weights)
    roll <= weights[1] && return Pierce
    roll <= weights[1] + weights[2] && return Multiball
    return Laser
end

function maybe_drop_powerup!(game::Game, center::Point2f)
    p = game.powerups
    cfg = game.cfg.powerup
    if p.drops_left > 0 && rand(game.rng, Float32) <= cfg.drop_probability
        push!(p.items, PowerupItem(center, V2(0f0, cfg.item_start_speed), sample_powerup(game)))
        p.drops_left -= 1
    end
    nothing
end

function activate_powerup!(game::Game, kind::PowerupKind)
    p = game.powerups
    cfg = game.cfg.powerup
    if kind == Pierce
        p.pierce_ttl = max(p.pierce_ttl, cfg.pierce_duration)
    elseif kind == Laser
        p.laser_ttl = max(p.laser_ttl, cfg.laser_duration)
        p.next_shot = 0f0
    elseif kind == Multiball
        n = max(cfg.multiball_count, 0)
        n == 0 && return
        arc = cfg.multiball_arc_radians
        angles = n == 1 ? (0f0,) : LinRange(-arc / 2, arc / 2, n)
        speed = norm(game.balls.main.vel)
        for angle in angles
            vel = rotate_velocity(game.balls.main.vel, Float32(angle))
            vel = norm(vel) > 0f0 ? vel * (speed / norm(vel)) : game.balls.main.vel
            push!(game.balls.extras, Ball(game.balls.main.pos, vel, cfg.child_ttl))
        end
    end
    nothing
end

function hit_brick!(game::Game, index::Int, multiplier::Float32; can_drop::Bool=true)
    brick = game.level.bricks[index]
    x1, y1, x2, y2 = rect_bounds(brick.rect)
    center = P2((x1 + x2) / 2, (y1 + y2) / 2)
    color = brick.color
    brick.hp -= 1
    if brick.hp <= 0
        add_particles!(game, center, color, game.cfg.fx.destroyed_particles,
            game.cfg.fx.destroyed_speed_range_at_800, game.cfg.fx.destroyed_ttl_range)
        deleteat!(game.level.bricks, index)
        game.score += Int(round(game.cfg.score.destroyed_brick * multiplier))
        can_drop && maybe_drop_powerup!(game, center)
    else
        brick.flash = game.cfg.fx.flash_duration
        brick.color = hp_color(brick.hp)
        add_particles!(game, center, color, game.cfg.fx.damaged_particles,
            game.cfg.fx.damaged_speed_range_at_800, game.cfg.fx.damaged_ttl_range)
        game.score += Int(round(game.cfg.score.damaged_brick * multiplier))
    end
    nothing
end

function register_combo_hit!(game::Game)
    game.combo.count += 1
    return score_multiplier(game)
end

function paddle_rect(game::Game)
    p = game.paddle
    return rectf(p.x, p.y, p.w, p.h)
end

function bounce_from_paddle!(game::Game, ball::Ball)
    p = game.paddle
    rel = clamp((ball.pos[1] - (p.x + p.w / 2)) / (p.w / 2), -1f0, 1f0)
    speed = norm(ball.vel)
    min_angle = deg2rad(game.cfg.ball.min_bounce_degrees)
    max_angle = deg2rad(game.cfg.ball.max_bounce_degrees)
    angle = min_angle + (max_angle - min_angle) * abs(rel)
    direction_x = (rel == 0f0 ? sign(ball.vel[1] == 0f0 ? 1f0 : ball.vel[1]) : sign(rel)) * sin(angle)
    direction_y = cos(angle)
    dir = normalize(V2(direction_x, max(direction_y, 0.2f0)))
    ball.vel = V2(dir[1] * speed, abs(dir[2] * speed))
    ball.pos = P2(ball.pos[1], p.y + p.h + ball_radius(game.cfg) + 0.1f0)
    reset_combo!(game)
    nothing
end

function step_ball!(game::Game, ball::Ball, dt::Float32)
    r = ball_radius(game.cfg)
    previous = ball.pos
    ball.pos = P2(ball.pos[1] + ball.vel[1] * dt, ball.pos[2] + ball.vel[2] * dt)

    if ball.pos[1] - r < 0f0
        ball.pos = P2(r, ball.pos[2])
        ball.vel = V2(abs(ball.vel[1]), ball.vel[2])
    elseif ball.pos[1] + r > game.cfg.world.width
        ball.pos = P2(game.cfg.world.width - r, ball.pos[2])
        ball.vel = V2(-abs(ball.vel[1]), ball.vel[2])
    end
    if ball.pos[2] + r > game.cfg.world.height
        ball.pos = P2(ball.pos[1], game.cfg.world.height - r)
        ball.vel = V2(ball.vel[1], -abs(ball.vel[2]))
    end

    if ball.vel[2] < 0f0 && circle_rect_overlap(ball.pos, r, paddle_rect(game))
        bounce_from_paddle!(game, ball)
    end

    for i in eachindex(game.level.bricks)
        brick = game.level.bricks[i]
        if circle_rect_overlap(ball.pos, r, brick.rect)
            normal = collision_normal(previous, ball.pos, r, brick.rect)
            multiplier = register_combo_hit!(game)
            hit_brick!(game, i, multiplier)
            if game.powerups.pierce_ttl > 0f0
                jitter = (rand(game.rng, Float32) - 0.5f0) * 0.08f0
                ball.vel = rotate_velocity(ball.vel, jitter)
            else
                normal[1] != 0f0 && (ball.vel = V2(-ball.vel[1], ball.vel[2]))
                normal[2] != 0f0 && (ball.vel = V2(ball.vel[1], -ball.vel[2]))
                ball.pos = P2(ball.pos[1] + normal[1] * 0.5f0, ball.pos[2] + normal[2] * 0.5f0)
            end
            break
        end
    end
    ball.vel = clamp_speed(ball.vel, game.cfg.ball.max_speed)
    return ball.pos[2] - r < 0f0
end

function update_main_ball!(game::Game, dt::Float32)
    if !game.balls.launched
        r = ball_radius(game.cfg)
        game.balls.main.pos = P2(game.paddle.x + game.paddle.w / 2, game.paddle.y + game.paddle.h + r + 1f0)
        empty!(game.balls.trail)
        return
    end

    dropped = step_ball!(game, game.balls.main, dt)
    if dropped && !isempty(game.balls.extras)
        promoted = pop!(game.balls.extras)
        game.balls.main.pos = promoted.pos
        game.balls.main.vel = promoted.vel
        game.balls.main.ttl = Inf32
        empty!(game.balls.trail)
        dropped = false
    end
    dropped && lose_life!(game)
    nothing
end

function update_extra_balls!(game::Game, dt::Float32)
    i = length(game.balls.extras)
    while i >= 1
        ball = game.balls.extras[i]
        ball.ttl -= dt
        dropped = ball.ttl <= 0f0 || step_ball!(game, ball, dt)
        dropped && deleteat!(game.balls.extras, i)
        i -= 1
    end
    nothing
end

function update_lasers!(game::Game, dt::Float32)
    p = game.powerups
    cfg = game.cfg.powerup
    if p.laser_ttl > 0f0
        p.next_shot -= dt
        if p.next_shot <= 0f0
            offset = game.paddle.w * 0.35f0
            y = game.paddle.y + game.paddle.h + 2f0
            push!(p.shots, LaserShot(P2(game.paddle.x + offset, y), V2(0f0, cfg.shot_speed), cfg.shot_ttl))
            push!(p.shots, LaserShot(P2(game.paddle.x + game.paddle.w - offset, y), V2(0f0, cfg.shot_speed), cfg.shot_ttl))
            p.next_shot = cfg.shot_cooldown
        end
    end

    hit_radius = cfg.shot_hit_radius_at_800 * scale_x(game.cfg)
    i = length(p.shots)
    while i >= 1
        shot = p.shots[i]
        shot.ttl -= dt
        shot.pos = P2(shot.pos[1] + shot.vel[1] * dt, shot.pos[2] + shot.vel[2] * dt)
        remove = shot.ttl <= 0f0 || shot.pos[2] > game.cfg.world.height
        if !remove
            for bi in eachindex(game.level.bricks)
                if circle_rect_overlap(shot.pos, hit_radius, game.level.bricks[bi].rect)
                    hit_brick!(game, bi, 1f0)
                    remove = true
                    break
                end
            end
        end
        remove && deleteat!(p.shots, i)
        i -= 1
    end
    nothing
end

function update_powerup_items!(game::Game, dt::Float32)
    cfg = game.cfg.powerup
    pickup_radius = cfg.item_marker_size_at_800 * scale_x(game.cfg) * cfg.item_pickup_radius_factor
    pad = paddle_rect(game)
    i = length(game.powerups.items)
    while i >= 1
        item = game.powerups.items[i]
        item.vel = V2(item.vel[1] * cfg.item_damping, item.vel[2] - cfg.item_gravity * dt)
        item.pos = P2(item.pos[1] + item.vel[1] * dt, item.pos[2] + item.vel[2] * dt)
        if circle_rect_overlap(item.pos, pickup_radius, pad)
            activate_powerup!(game, item.kind)
            deleteat!(game.powerups.items, i)
        elseif item.pos[2] < 0f0
            deleteat!(game.powerups.items, i)
        end
        i -= 1
    end
    nothing
end

function update_particles!(game::Game, dt::Float32)
    i = length(game.fx.particles)
    while i >= 1
        p = game.fx.particles[i]
        p.ttl -= dt
        if p.ttl <= 0f0
            deleteat!(game.fx.particles, i)
        else
            p.pos = P2(p.pos[1] + p.vel[1] * dt, p.pos[2] + p.vel[2] * dt)
            p.vel = V2(p.vel[1] * game.cfg.fx.particle_damping,
                (p.vel[2] - game.cfg.fx.particle_gravity * dt) * game.cfg.fx.particle_damping)
        end
        i -= 1
    end
    nothing
end

function update_timers!(game::Game, dt::Float32)
    for brick in game.level.bricks
        brick.flash = max(0f0, brick.flash - dt)
    end
    game.powerups.pierce_ttl = max(0f0, game.powerups.pierce_ttl - dt)
    game.powerups.laser_ttl = max(0f0, game.powerups.laser_ttl - dt)
    nothing
end

function update_trail!(game::Game)
    if !game.balls.launched
        empty!(game.balls.trail)
        return
    end
    push!(game.balls.trail, game.balls.main.pos)
    overflow = length(game.balls.trail) - game.cfg.ball.trail_length
    overflow > 0 && deleteat!(game.balls.trail, 1:overflow)
    nothing
end

function clear_level_if_needed!(game::Game)
    isempty(game.level.bricks) || return
    next_level = max(game.level.index + 1, 2)
    game.level = make_level(game.rng, game.cfg, next_level)
    reset_powerups!(game)
    reset_combo!(game)
    reset_ball!(game)
    nothing
end

function move_paddle!(game::Game, direction::Real, dt::Float32)
    dx = Float32(direction) * game.paddle.speed * dt
    game.paddle.x = clamp(game.paddle.x + dx, 0f0, game.cfg.world.width - game.paddle.w)
    nothing
end

function handle_input!(game::Game, scene, dt::Float32)
    direction = 0f0
    (ispressed(scene, Keyboard.left) || ispressed(scene, Keyboard.a)) && (direction -= 1f0)
    (ispressed(scene, Keyboard.right) || ispressed(scene, Keyboard.d)) && (direction += 1f0)
    move_paddle!(game, direction, dt)
    nothing
end

function step_game!(game::Game, scene, dt::Float32)
    handle_input!(game, scene, dt)
    update_lasers!(game, dt)
    update_main_ball!(game, dt)
    update_extra_balls!(game, dt)
    update_powerup_items!(game, dt)
    update_particles!(game, dt)
    update_timers!(game, dt)
    update_trail!(game)
    clear_level_if_needed!(game)
    nothing
end

function brick_display_color(game::Game, brick::Brick)
    factor = game.cfg.fx.flash_duration <= 0f0 ? 0f0 : clamp(brick.flash / game.cfg.fx.flash_duration, 0f0, 1f0) * 0.6f0
    return factor > 0f0 ? mix_rgba(brick.color, COLOR_BALL, factor) : brick.color
end

function sync_view!(view::View, game::Game)
    view.bricks[] = [brick.rect for brick in game.level.bricks]
    view.brick_colors[] = [brick_display_color(game, brick) for brick in game.level.bricks]
    view.paddle[] = paddle_rect(game)
    view.balls[] = vcat([game.balls.main.pos], [ball.pos for ball in game.balls.extras])
    ball_color = game.powerups.pierce_ttl > 0f0 ? COLOR_PU_LASER : COLOR_BALL
    view.ball_colors[] = fill(ball_color, 1 + length(game.balls.extras))
    view.trail_points[] = copy(game.balls.trail)
    n = length(game.balls.trail)
    tbase = game.powerups.pierce_ttl > 0f0 ? COLOR_PU_LASER : COLOR_BALL
    alphas = n == 0 ? Float32[] : (n == 1 ? Float32[0.35f0] : collect(LinRange{Float32}(0.06f0, 0.35f0, n)))
    view.trail_colors[] = [RGBAf(tbase.r, tbase.g, tbase.b, a) for a in alphas]
    view.items[] = [item.pos for item in game.powerups.items]
    view.item_colors[] = [powerup_color(item.kind) for item in game.powerups.items]
    view.shots[] = [shot.pos for shot in game.powerups.shots]
    view.particles[] = [p.pos for p in game.fx.particles]
    view.particle_colors[] = [RGBAf(p.color.r, p.color.g, p.color.b, clamp(p.ttl / p.ttl_max, 0f0, 1f0) * 0.9f0) for p in game.fx.particles]
    view.score_text[] = "Score: $(game.score)"
    view.lives_text[] = "Lives: $(game.lives)"
    view.level_text[] = "Level: $(game.level.index)"
    view.pierce_text[] = game.powerups.pierce_ttl > 0f0 ? @sprintf("Pierce %.1fs", game.powerups.pierce_ttl) : ""
    view.laser_text[] = game.powerups.laser_ttl > 0f0 ? @sprintf("Laser %.1fs", game.powerups.laser_ttl) : ""
    if game.combo.count > 0
        view.combo_text[] = "COMBO x$(game.combo.count)  x$(round(score_multiplier(game); digits=1))"
        view.combo_color[] = RGBAf(COLOR_TEXT.r, COLOR_TEXT.g, COLOR_TEXT.b, 1f0)
    else
        view.combo_text[] = ""
        view.combo_color[] = RGBAf(COLOR_TEXT.r, COLOR_TEXT.g, COLOR_TEXT.b, 0f0)
    end
    hint = game.balls.launched ? "" : "Press SPACE to launch  |  A/D or Left/Right move  |  P pause\n[ / ] prev/next level  |  R reset"
    view.hint_text[] = hint
    line_count = isempty(hint) ? 0 : count(==('\n'), hint) + 1
    hint_height = Float32(HINT_FONT_SIZE) * HINT_LINE_HEIGHT * line_count
    hint_y = game.cfg.world.height * 0.5f0
    view.hint_bg[] = isempty(hint) ? Rect2[] : [rectf(0f0, hint_y - hint_height / 2, game.cfg.world.width, hint_height)]
    nothing
end

function restore!(game::Game, snap::Game)
    game.rng = deepcopy(snap.rng)
    game.paddle = deepcopy(snap.paddle)
    game.balls = deepcopy(snap.balls)
    game.level = deepcopy(snap.level)
    game.powerups = deepcopy(snap.powerups)
    game.fx = deepcopy(snap.fx)
    game.combo = deepcopy(snap.combo)
    game.score = snap.score
    game.lives = snap.lives
    game.paused = snap.paused
    nothing
end

function with_snapshot(f::Function, game::Game, view::View)
    snap = deepcopy(game)
    try
        f()
    catch err
        @warn "warmup! failed" exception = (err, catch_backtrace())
    finally
        restore!(game, snap)
        sync_view!(view, game)
    end
    nothing
end

function warmup!(scene, game::Game, view::View)
    with_snapshot(game, view) do
        dt, r = game.cfg.world.fixed_dt, ball_radius(game.cfg)
        warm_step!() = (step_game!(game, scene, dt); sync_view!(view, game); yield())
        move_paddle!(game, 1f0, dt)
        sync_view!(view, game)
        yield()
        game.balls.launched = false
        warm_step!()
        game.balls.launched = true
        warm_step!()
        game.balls.main.pos = P2(game.paddle.x + game.paddle.w / 2, game.paddle.y + game.paddle.h + r + 2f0)
        game.balls.main.vel = V2(0f0, -260f0)
        warm_step!()
        if !isempty(game.level.bricks)
            x1, y1, x2, _ = rect_bounds(game.level.bricks[1].rect)
            game.balls.main.pos = P2((x1 + x2) / 2, y1 - r - 1f0)
            game.balls.main.vel = V2(0f0, 300f0)
            warm_step!()
        end
        activate_powerup!(game, Pierce)
        activate_powerup!(game, Multiball)
        activate_powerup!(game, Laser)
        push!(game.powerups.items, PowerupItem(P2(game.paddle.x + game.paddle.w / 2, game.paddle.y + game.paddle.h / 2), V2(0f0, 0f0), Pierce))
        warm_step!()
    end
    nothing
end

function create_view!(fig, ax, game::Game)
    cfg = game.cfg
    view = View(
        Observable(Rect2[]),
        Observable(RGBAf[]),
        Observable(paddle_rect(game)),
        Observable(Point2f[]),
        Observable(RGBAf[]),
        Observable(Point2f[]),
        Observable(RGBAf[]),
        Observable(Point2f[]),
        Observable(RGBAf[]),
        Observable(Point2f[]),
        Observable(Point2f[]),
        Observable(RGBAf[]),
        Observable(""),
        Observable(""),
        Observable(""),
        Observable(""),
        Observable(""),
        Observable(""),
        Observable(RGBAf(COLOR_TEXT.r, COLOR_TEXT.g, COLOR_TEXT.b, 0f0)),
        Observable(Rect2[]),
        Observable(""),
    )
    sync_view!(view, game)

    poly!(ax, view.bricks; color=view.brick_colors, strokecolor=:transparent)
    scatter!(ax, view.items; marker=:rect, markersize=cfg.powerup.item_marker_size_at_800 * scale_x(cfg), color=view.item_colors)
    scatter!(ax, view.shots; marker=:circle, markersize=8f0 * scale_x(cfg), color=COLOR_LASER_SHOT)
    scatter!(ax, view.particles; marker=:circle, markersize=6f0 * scale_x(cfg), color=view.particle_colors)
    scatter!(ax, view.trail_points; marker=:circle, markersize=2f0 * ball_radius(cfg), color=view.trail_colors)
    poly!(ax, view.paddle; color=COLOR_PADDLE, strokecolor=:transparent)
    scatter!(ax, view.balls; marker=:circle, markersize=2f0 * ball_radius(cfg), color=view.ball_colors)

    hud = rectf(0f0, cfg.world.height - 36f0 * scale_y(cfg), cfg.world.width, 36f0 * scale_y(cfg))
    poly!(ax, hud; color=COLOR_HUDBG, strokecolor=:transparent)
    text!(ax, view.score_text; position=P2(10f0, cfg.world.height - 4f0), align=(:left, :top), color=COLOR_TEXT, fontsize=20)
    text!(ax, view.lives_text; position=P2(cfg.world.width / 2, cfg.world.height - 4f0), align=(:center, :top), color=COLOR_TEXT, fontsize=20)
    text!(ax, view.level_text; position=P2(cfg.world.width - 10f0, cfg.world.height - 4f0), align=(:right, :top), color=COLOR_TEXT, fontsize=20)
    text!(ax, view.pierce_text; position=P2(cfg.world.width * 0.12f0, cfg.world.height - 4f0), align=(:left, :top), color=COLOR_PU_PIERCE, fontsize=16)
    text!(ax, view.laser_text; position=P2(cfg.world.width * 0.28f0, cfg.world.height - 4f0), align=(:left, :top), color=COLOR_PU_LASER, fontsize=16)
    text!(ax, view.combo_text; position=P2(cfg.world.width * 0.72f0, cfg.world.height - 4f0), align=(:center, :top), color=view.combo_color, fontsize=20)
    poly!(ax, view.hint_bg; color=COLOR_HUDBG, strokecolor=:transparent)
    text!(ax, view.hint_text; position=P2(cfg.world.width / 2, cfg.world.height * 0.5f0), align=(:center, :center), color=COLOR_TEXT, fontsize=HINT_FONT_SIZE)
    return view
end

function breakout()
    cfg = GameConfig()
    game = new_game(cfg)
    fig = Figure(size=(Int(cfg.world.width), Int(cfg.world.height)), backgroundcolor=COLOR_BG)
    ax = Axis(fig[1, 1]; limits=((0f0, cfg.world.width), (0f0, cfg.world.height)),
        aspect=DataAspect(), backgroundcolor=COLOR_BG,
        xticksvisible=false, yticksvisible=false, xgridvisible=false, ygridvisible=false,
        xlabelvisible=false, ylabelvisible=false, titlevisible=false)
    hidedecorations!(ax)
    view = create_view!(fig, ax, game)

    display(fig)
    scene = ax.scene
    warmup!(scene, game, view)

    on(events(scene).keyboardbutton) do event
        if event.action == Keyboard.press
            event.key == Keyboard.space && (game.balls.launched = true)
            event.key == Keyboard.p && (game.paused = !game.paused)
            event.key == Keyboard.left_bracket && set_level!(game, game.level.index - 1)
            event.key == Keyboard.right_bracket && set_level!(game, game.level.index + 1)
            event.key == Keyboard.r && reset_run!(game)
            event.key == Keyboard.escape && close(fig)
            sync_view!(view, game)
        end
        nothing
    end

    previous = time()
    accumulator = 0.0
    @async while isopen(scene)
        now = time()
        accumulator += now - previous
        previous = now
        while accumulator >= cfg.world.fixed_dt
            if !game.paused
                try
                    step_game!(game, scene, cfg.world.fixed_dt)
                    sync_view!(view, game)
                catch err
                    @error "step_game! crashed" exception=(err, catch_backtrace())
                    game.paused = true
                end
            end
            accumulator -= cfg.world.fixed_dt
        end
        sleep(0.001)
    end
    return fig
end

breakout()
