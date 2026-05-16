package com.microapp.calculator.observability;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Preloads MongoDB driver classes that are used by the driver's background
 * server-monitor threads. In Spring Boot executable JARs, very-late class
 * loading by those background threads can otherwise appear in APM as a
 * NoClassDefFoundError with "ZipFile closed" / "Stream closed" when the
 * application is stopping or when the nested JAR class loader is under pressure.
 *
 * This class does not initialize a MongoDB connection. It only asks the active
 * application class loader to resolve the driver classes while the application
 * class loader is unquestionably open.
 */
public final class MongoDriverClassPreloader {
    private static final Logger log = LoggerFactory.getLogger(MongoDriverClassPreloader.class);

    private static final String[] DRIVER_CLASSES = {
            "org.bson.Document",
            "com.mongodb.client.MongoClient",
            "com.mongodb.client.MongoClients",
            "com.mongodb.internal.connection.InternalStreamConnection",
            "com.mongodb.internal.connection.InternalStreamConnectionFactory",
            "com.mongodb.internal.connection.InternalConnectionFactory",
            "com.mongodb.internal.connection.DefaultServerMonitor",
            "com.mongodb.internal.connection.SocketStream"
    };

    private MongoDriverClassPreloader() {
    }

    public static void preload() {
        ClassLoader classLoader = MongoDriverClassPreloader.class.getClassLoader();
        for (String className : DRIVER_CLASSES) {
            try {
                Class.forName(className, false, classLoader);
            } catch (Throwable ex) {
                log.warn("event=mongodb.driver.preload.failed class={} exception={} message={}",
                        className,
                        ex.getClass().getName(),
                        ex.getMessage() == null ? "" : ex.getMessage());
            }
        }
    }
}
