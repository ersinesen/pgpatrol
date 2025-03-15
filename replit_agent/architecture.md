# PostgreSQL Monitor Architecture

## Overview

PostgreSQL Monitor is a cross-platform application built with Flutter and Dart, designed to provide real-time monitoring of PostgreSQL database instances. The application follows an Apple-inspired minimalist design aesthetic and is intended to run on multiple platforms, with particular support for web deployment on Replit.

## System Architecture

The application follows a client-server architecture with clear separation of concerns:

1. **Frontend Layer (Flutter/Dart)** - Contains screens and widgets responsible for UI rendering
2. **API Layer (Node.js)** - Middleware that securely connects to PostgreSQL and exposes data via RESTful endpoints
3. **Database Layer (PostgreSQL)** - The monitored database instance

This architecture enhances security by preventing direct database access from the client. The application uses a reactive programming approach with Dart streams to handle real-time data updates from the API.

## Key Components

### Models

Located in `lib/models/`, these classes define the data structures used throughout the application:

- `connection_status.dart` - Represents the current state of the database connection
- `database_stats.dart` - Contains metrics about database size, tables, and active connections
- `query_log.dart` - Holds information about executed queries for analysis
- `resource_stats.dart` - Tracks system resource utilization metrics with time-series data

Models are immutable and use the copyWith pattern to create new instances with modified properties.

### Services

Located in `lib/services/`, these classes handle the business logic and external communication:

- `api_database_service.dart` - The central service that communicates with the Node.js API to fetch PostgreSQL metrics
- `connection_manager.dart` - Manages server connections and authentication

The service layer uses Dart streams extensively to provide real-time updates to the UI. The API service maintains separate streams for different types of monitoring data (connection status, query logs, resource stats, etc.) allowing components to subscribe only to the data they need. This architecture isolates the Flutter frontend from direct database access, enhancing security.

### Screens

Located in `lib/screens/`, these classes define the different views of the application:

- `dashboard_screen.dart` - The main screen displaying an overview of database metrics
- `query_logs_screen.dart` - Shows detailed query information and execution times
- `query_performance_screen.dart` - Provides analysis of query performance
- `resource_utilization_screen.dart` - Displays system resource metrics like CPU and memory usage

### Widgets

Located in `lib/widgets/`, these are reusable UI components used across screens:

- `metric_card.dart` - Displays individual metrics in a card format
- `performance_chart.dart` - Renders time-series data as charts
- `query_log_table.dart` - Displays query logs in a tabular format
- `status_indicator.dart` - Shows connection status with visual indicators

### Theme

Located in `lib/theme/`, this handles the application's visual styling:

- `app_theme.dart` - Defines colors, text styles, and component themes for light and dark mode

## Data Flow

1. The application initiates a connection to PostgreSQL using the `DatabaseService`
2. Upon successful connection, the service starts collecting metrics at regular intervals
3. Metrics are exposed as Dart streams which UI components can subscribe to
4. When new data is available, the UI automatically updates to reflect the changes
5. User interactions (like filtering query logs or changing time ranges) are handled locally without requiring new database queries

The reactive approach minimizes unnecessary database queries and ensures the UI always reflects the latest data.

## External Dependencies

The application relies on the following key external packages:

- `postgres` (v2.6.1) - For connecting to and querying PostgreSQL databases
- `syncfusion_flutter_charts` (v22.1.34) - For rendering performance charts and graphs
- `intl` (v0.18.1) - For date and number formatting
- `cupertino_icons` (v1.0.5) - For iOS-style icons

## Deployment Strategy

The application is configured for multiple deployment scenarios:

1. **Web Deployment** - The primary deployment target, with web-specific optimizations in place and configurations in `.replit` and other web-related files
2. **Mobile Deployment** - The structure supports iOS and Android deployment, though web appears to be the current focus

The web deployment leverages Flutter's ability to compile to JavaScript, allowing the application to run in modern browsers. The application is designed to be hosted on any standard web server or platform that supports static file hosting.

## Authentication and Security

The application appears to connect directly to PostgreSQL using connection details provided via environment variables. There is no built-in user authentication system apparent in the code, suggesting that security should be handled via:

1. Network-level controls (VPN, SSH tunneling, etc.)
2. PostgreSQL's native user authentication
3. Deployment-specific security measures

## Future Considerations

Based on the current architecture, potential areas for enhancement include:

1. **Authentication Layer** - Adding user authentication to protect access to database metrics
2. **Multiple Database Support** - Extending the service layer to monitor multiple PostgreSQL instances simultaneously
3. **Alerting System** - Implementing alerts for critical database issues
4. **Historical Data Storage** - Adding capability to store and analyze historical performance data