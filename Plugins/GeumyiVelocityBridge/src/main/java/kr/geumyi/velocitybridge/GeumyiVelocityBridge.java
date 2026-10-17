package kr.geumyi.velocitybridge;

import com.google.inject.Inject;
import com.velocitypowered.api.event.Subscribe;
import com.velocitypowered.api.event.proxy.ProxyInitializeEvent;
import com.velocitypowered.api.plugin.Plugin;
import com.velocitypowered.api.proxy.ProxyServer;
import org.slf4j.Logger;

/**
 * Canary development shell. No socket, plugin message channel, command, file
 * write, scheduler task, player transfer, or lifecycle-control operation.
 *
 * Do NOT copy to a production plugins folder. The installed proxy API
 * version and Java runtime have not been independently attested.
 */
@Plugin(
    id = "geumyi-velocity-bridge",
    name = "Geumyi Velocity Bridge - Disabled Prototype",
    version = "0.1.0-canary-dev",
    description = "No-op compatibility shell; control is unconditionally disabled"
)
public final class GeumyiVelocityBridge {
    private final ProxyServer proxy;
    private final Logger logger;

    @Inject
    public GeumyiVelocityBridge(ProxyServer proxy, Logger logger) {
        this.proxy = proxy;
        this.logger = logger;
    }

    @Subscribe
    public void onInitialize(ProxyInitializeEvent event) {
        // The proxy may have a different version from our compile target.
        // Logging a label is NOT compatibility validation.
        logger.warn("Geumyi Velocity Bridge development shell loaded on version {}. "
                + "All external communication and lifecycle controls remain disabled.",
                proxy.getVersion().getVersion());
    }

    // Deliberately no authenticated command handler yet, and no server
    // network listener; even the HMAC protocol model is not invoked here.
}
