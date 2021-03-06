/**
System management module.

Copyright: © 2015-2016 Claude Merle
Authors: Claude Merle
License: This file is part of EntitySysD.

EntitySysD is free software: you can redistribute it and/or modify it
under the terms of the Lesser GNU General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

EntitySysD is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
Lesser GNU General Public License for more details.

You should have received a copy of the Lesser GNU General Public License
along with EntitySysD. If not, see $(LINK http://www.gnu.org/licenses/).
*/

import std.container;
import std.math;
import std.random;
import std.stdio;

import derelict.sdl2.sdl;

import entitysysd;


//*** Helpers ***
struct Vector2f
{
    float x, y;
}

struct Color
{
    ubyte r, g, b;
}


//*** Component structures ***
@component struct Body
{
    Vector2f position;
    Vector2f direction;
}

@component struct Renderable
{
    float radius;
    Color color;
}


@component struct Particle
{
    Color color;
    float radius, alpha, d;
}


@component struct Collideable
{
    float radius;
}

//*** Random-number-generator utility function ***
float r(int a, float b = 0)
{
    return cast(float)(uniform(0, a * 1000) + b * 1000) / 1000.0;
}

//*** Event struct ***

@event struct CollisionEvent
{
    Entity a, b;
}


//*** System classes ***

class SpawnSystem : System
{
public:
    this(SDL_Window* window, int count)
    {
        SDL_GetWindowSize(window, &mSizeX, &mSizeY);
        mCount = count;
    }

    override void run(EntityManager es, EventManager events, Duration dt)
    {
        int c = 0;
        //ComponentHandle<Collideable> collideable;
        foreach (entity; es.entitiesWith!Collideable)
            c++;

        for (int i = 0; i < mCount - c; i++)
        {
            Entity entity = es.create();

            // Mark as collideable (explosion particles will not be collideable).
            //todo use "assign" to merge the 2 next instructions
            float radius = r(10, 5);
            entity.register!Collideable();
            entity.component!Collideable.radius = radius;
            //collideable = entity.assign<Collideable>(r(10, 5));

            // "Physical" attributes.
            auto bod = entity.register!Body();
            bod.position  = Vector2f(r(mSizeX), r(mSizeY));
            bod.direction = Vector2f(r(300, -150), r(300, -150));

            // Shape to apply to entity.
            auto ren = entity.register!Renderable();
            ren.radius = radius;
            ren.color  = Color(cast(ubyte)r(128, 127),
                               cast(ubyte)r(128, 127),
                               cast(ubyte)r(128, 127));
        }
    }

private:
    int mSizeX, mSizeY;
    int mCount;
};


// Updates a body's position and rotation.
class MoveSystem : System
{
public:
    this(SDL_Window* window)
    {
        SDL_GetWindowSize(window, &mSizeX, &mSizeY);
    }

    override void run(EntityManager es, EventManager events, Duration dt)
    {
        foreach (entity, bod; es.entitiesWith!Body)
        {
            // update position
            bod.position.x += bod.direction.x * dt.total!"msecs" / 1000.0;
            bod.position.y += bod.direction.y * dt.total!"msecs" / 1000.0;

            // make it bounce on the edges of the window
            if (bod.position.x < 0.0)
            {
                bod.position.x = -bod.position.x;
                bod.direction.x = -bod.direction.x;
            }
            else if (bod.position.x >= mSizeX)
            {
                bod.position.x = 2 * mSizeX - bod.position.x;
                bod.direction.x = -bod.direction.x;
            }

            if (bod.position.y < 0.0)
            {
                bod.position.y = -bod.position.y;
                bod.direction.y = -bod.direction.y;
            }
            else if (bod.position.y >= mSizeY)
            {
                bod.position.y = 2 * mSizeY - bod.position.y;
                bod.direction.y = -bod.direction.y;
            }
        }
    }
private:
    int mSizeX, mSizeY;
}


// Determines if two Collideable bodies have collided. If they have it emits a
// CollisionEvent. This is used by ExplosionSystem to create explosion
// particles, but it could be used by a SoundSystem to play an explosion
// sound, etc..
//
// Uses a fairly rudimentary 2D partition system, but performs reasonably well.
class CollisionSystem : System
{
public:
    this(SDL_Window* window)
    {
        SDL_GetWindowSize(window, &mSizeX, &mSizeY);
        mGrid.length = mSizeX * mSizeY;
    }

    override void run(EntityManager es, EventManager events, Duration dt)
    {
        reset();
        collect(es);
        collide(events);
    }

private:
    enum int mPartitions = 200;

    struct Candidate
    {
        Vector2f position;
        float radius;
        Entity entity;
    };

    Candidate[][] mGrid;
    int mSizeX, mSizeY;

    void reset()
    {
        foreach (ref candidates; mGrid)
            candidates.length = 0;
    }

    void collect(EntityManager entities)
    {
        foreach (entity, bod, col; entities.entitiesWith!(Body, Collideable))
        {
            auto left   = cast(int)(bod.position.x - col.radius) / mPartitions;
            auto top    = cast(int)(bod.position.y - col.radius) / mPartitions;
            auto right  = cast(int)(bod.position.x + col.radius) / mPartitions;
            auto bottom = cast(int)(bod.position.y + col.radius) / mPartitions;

            auto candidate = Candidate(bod.position, col.radius, entity);
            uint[4] slots = [left + top * mSizeX,     right + top * mSizeX,
                             left  + bottom * mSizeX, right + bottom * mSizeX];
            mGrid[slots[0]] ~= candidate;
            if (slots[0] != slots[1])
                mGrid[slots[1]] ~= candidate;
            if (slots[1] != slots[2])
                mGrid[slots[2]] ~= candidate;
            if (slots[2] != slots[3])
                mGrid[slots[3]] ~= candidate;
        }
    }

    void collide(EventManager events)
    {
        foreach (candidates; mGrid)
            foreach (ref candidateA; candidates)
                foreach (ref candidateB; candidates)
                {
                    if (candidateA.entity == candidateB.entity)
                        continue;
                    if (collided(candidateA, candidateB))
                        events.emit!CollisionEvent(candidateA.entity,
                                                   candidateB.entity);
            }
    }

    float length2(const ref Vector2f v)
    {
        return v.x * v.x + v.y * v.y;
    }

    bool collided(in ref Candidate a, in ref Candidate b)
    {
        auto ab = Vector2f(a.position.x - b.position.x,
                           a.position.y - b.position.y);
        float radius2 = a.radius + b.radius;
        radius2 *= radius2;
        return length2(ab) < radius2;
    }
}


class ParticleSystem : System
{
public:
    override void run(EntityManager es, EventManager events, Duration dt)
    {
        foreach (entity, particle; es.entitiesWith!Particle)
        {
            particle.alpha -= particle.d * dt.total!"msecs";
            if (particle.alpha <= 0)
                entity.destroy();
        }
    }
}


class ParticleRenderSystem : System
{
public:
    this(SDL_Renderer* renderer)
    {
        mpRenderer = renderer;
    }

    override void run(EntityManager es, EventManager events, Duration dt)
    {
        foreach (entity, bod, particle; es.entitiesWith!(Body, Particle))
        {
            auto radius = particle.radius;
            // Change color
            SDL_SetRenderDrawColor(mpRenderer,
                                   particle.color.r,
                                   particle.color.g,
                                   particle.color.b,
                                   cast(ubyte)particle.alpha );
            SDL_Rect rect;
            rect.x = cast(int)(bod.position.x - radius);
            rect.y = cast(int)(bod.position.y - radius);
            rect.w = cast(int)(radius * 2);
            rect.h = cast(int)(radius * 2);
            SDL_RenderFillRect(mpRenderer, &rect);
        }
    }

private:
    SDL_Renderer* mpRenderer;
}


// For any two colliding bodies, destroys the bodies and emits a bunch of bodgy explosion particles.
class ExplosionSystem : System, Receiver!CollisionEvent
{
public:
    override void run(EntityManager es, EventManager events, Duration dt)
    {
        foreach (entity; mCollisions)
        {
            // the same entity might be detected by collision several times
            if (!entity.valid)
                continue;
            emitParticles(es, entity);
            entity.destroy();
        }
        while (!mCollisions.empty)
            mCollisions.removeFront();
    }

    void emitParticles(EntityManager es, Entity entity)
    {
        auto bod = entity.component!Body;
        auto ren = entity.component!Renderable;
        auto col = entity.component!Collideable;

        float area = (PI * col.radius * col.radius) / 3.0;
        for (int i = 0; i < area; i++)
        {
            Entity particle = es.create();

            float rotationd = r(720, 180);
            if (uniform(0, 2) == 0)
                rotationd = -rotationd;

            float offset = r(cast(int)col.radius, 1.0);
            float angle  = r(360) * PI / 180.0;

            auto partBody = particle.register!Body();
            partBody.position.x  = bod.position.x + offset * cos(angle);
            partBody.position.y  = bod.position.y + offset * sin(angle);
            partBody.direction.x = offset * 2 * cos(angle);
            partBody.direction.y = offset * 2 * sin(angle);

            float radius = r(3, 1);
            auto partPart = particle.register!Particle();
            partPart.color  = ren.color;
            partPart.radius = radius;
            partPart.alpha  = 200;
            partPart.d      = r(3, 1) / 2;
        }
    }

    void receive(CollisionEvent collision)
    {
        // Events are immutable, so we can't destroy the entities here. We defer
        // the work until the update loop.
        mCollisions.insertFront(collision.a);
        mCollisions.insertFront(collision.b);
    }

private:
    SList!Entity mCollisions;
}

// Render all Renderable entities
class RenderSystem : System
{
public:
    this(SDL_Renderer* renderer)
    {
        mpRenderer = renderer;
    }

    override void run(EntityManager es, EventManager events, Duration dt)
    {
        foreach (entity, bod, rdr; es.entitiesWith!(Body, Renderable))
        {
            auto radius = rdr.radius;
            // Change color
            SDL_SetRenderDrawColor(mpRenderer,
                                   rdr.color.r,
                                   rdr.color.g,
                                   rdr.color.b,
                                   255 );
            SDL_Rect rect;
            rect.x = cast(int)(bod.position.x - radius);
            rect.y = cast(int)(bod.position.y - radius);
            rect.w = cast(int)(radius * 2);
            rect.h = cast(int)(radius * 2);
            SDL_RenderFillRect(mpRenderer, &rect);
        }
    }

private:
    SDL_Renderer* mpRenderer;
}


class Application : EntitySysD
{
public:
    this(SDL_Renderer* renderer, SDL_Window* window)
    {
        super();
        systems.register(new SpawnSystem(window, 20));
        systems.register(new MoveSystem(window));
        systems.register(new CollisionSystem(window));
        systems.register(new ExplosionSystem);
        systems.register(new ParticleSystem);
        systems.register(new RenderSystem(renderer));
        systems.register(new ParticleRenderSystem(renderer));
    }

    void run(Duration dt)
    {
        systems.run(dt);
    }
}

void main()
{
    DerelictSDL2.load();
    scope(exit) DerelictSDL2.unload();

    if (SDL_Init(SDL_INIT_EVERYTHING) == -1)
        return;

    SDL_Window* window = SDL_CreateWindow("Server", 0, 0, 640, 480, 0);
    SDL_Renderer* renderer = SDL_CreateRenderer(window, -1, 0);
    SDL_RenderSetLogicalSize(renderer, 640, 480);

    auto app = new Application(renderer, window);

    bool loop = true;
    MonoTime timestamp = MonoTime.currTime;

    while (loop)
    {
        SDL_Event event;
        while (SDL_PollEvent(&event))
        {
            if (event.type == SDL_QUIT)
                loop = false;
        }

        SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255);
        SDL_RenderClear(renderer);

        app.run(dur!"msecs"(16));

        SDL_RenderPresent(renderer);

        MonoTime now = MonoTime.currTime;
        Duration timeElapsed = now - timestamp;
        long delay = 16 - timeElapsed.total!"msecs";
        if (delay < 0)
            delay = 0;

        // Add a 16msec delay to run at ~60 fps
        SDL_Delay(cast(uint)delay);
        timestamp = MonoTime.currTime;
    }
}