package org.bukkit.event;
import java.lang.annotation.*;
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.METHOD)
public @interface EventHandler { boolean ignoreCancelled() default false; }
