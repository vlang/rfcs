- Topic Name: `override`
- Start Date: `2022-06-26`
- RFC PR: [vlang/rfcs#00000](https://github.com/vlang/rfcs/pull/25)
- V Issue: *not applicable*

# Summary

Provide a way to override an external method.

# Motivation

There are places where overriding a foreign method is useful.
Picture a game represented as a `module`, this game has `struct`s representing a tree, an animal etc. Each `struct` has a set of methods.

Now, this game provides a modding API. The developers can then add new features and such, however adding a specific feature may require modifying some aspects of the gameplay. Developers may need to modify a specific method: they may need to override a foreign method.

# Guide-level explanation

*from [mooziii/explosive-chickens](https://github.com/mooziii/explosive-chickens/blob/main/src/main/java/me/obsilabor/explosivechickens/entity/ExplosiveChickenEntity.java)*
```java
package me.obsilabor.explosivechickens.entity;

import net.minecraft.entity.EntityType;
import net.minecraft.entity.damage.DamageSource;
import net.minecraft.entity.passive.ChickenEntity;
import net.minecraft.world.World;
import net.minecraft.world.explosion.Explosion;

public class ExplosiveChickenEntity extends ChickenEntity {
    public ExplosiveChickenEntity(EntityType<? extends ChickenEntity> entityType, World world) {
        super(entityType, world);
    }

    @Override
    public void onDeath(DamageSource damageSource) {
        super.onDeath(damageSource);
        world.createExplosion(this, this.getX(), this.getY(), this.getZ(), 3.5F, Explosion.DestructionType.BREAK);
    }
}
```

This is a code snippet from a [Minecraft](https://en.wikipedia.org/wiki/Minecraft) mod that makes chickens explode when they die.

In this code we create a new `ExplosiveChickenEntity` class, similar in any way to the already existing `ChickenEntity`. The only modification is that we are using the `@Override` [annotation](https://en.wikipedia.org/wiki/Java_annotation). We are overriding the `onDeath` method.

Inside the *new* `onDeath` method we call the *old* one and append a new instruction, an explosion.

---

The above Java code could be the below one in V.

*irrelevant parts from the Java code were stripped*
```v
import minecraft_stuff

struct ExplosiveChickenEntity {
    minecraft_stuff.ChickenEntity
}

[override: chicken]
fn (explosive_chicken ExplosiveChickenEntity) on_death(damage_source minecraft_stuff.DamageSource) {
    chicken.on_death(damage_source)
    minecraft_stuff.create_explosion(...)
}
```

# Reference-level explanation

As the name suggest, in Java this is an "annotation", it just helps the compiler and the developer. V isn't a permissive language, in V, using the `override` attribute should be mandatory.

To force people only using it when necessary and maintain good quality code, overriding should only be possible if the method is a foreign one (from an imported module). It can also be disabled on built-in types.

The override function should have the exact same signature as the override done.

# Drawbacks

Even with the limitation on only using it with imported module, people may be tempted to use it we not strictly necessary.

# Rationale and alternatives

The exact design of the attribute is left to be polished, it could be either `[override: name]`, `[override name]`, `[override: "name"]` or `[override "name"]`.

# Prior art

As said before, this is used in Java ([doc](https://www.geeksforgeeks.org/the-override-annotation-in-java/)), in Dart ([doc](https://dart.dev/guides/language/type-system#use-sound-parameter-types-when-overriding-methods)), in Kotlin ([doc](https://www.geeksforgeeks.org/overriding-rules-in-kotlin/)) and probably others.

This is also widely used and necessary in Minecraft modding, to override default behaviors of the game.

# Unresolved questions

\-

# Future possibilities

The `override` attribute can be extended to consts and functions.


