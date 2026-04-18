{
  "cli": {
    "version": ">= 16.0.0",
    "appVersionSource": "remote"
  },
  "build": {
    "development": {
      "developmentClient": true,
      "distribution": "internal"
    },
    "preview": {
      "distribution": "internal"
    },
    "dev-testflight": {
      "environment": "development",
      "channel": "development",
      "distribution": "store",
      "autoIncrement": true,
      "env": {
        "EXPO_PUBLIC_API_URL": "https://dev-api.{{PROJECT_SLUG}}.example.com"
      },
      "ios": {
        "buildConfiguration": "Release"
      }
    },
    "production": {
      "environment": "production",
      "channel": "production",
      "distribution": "store",
      "autoIncrement": true,
      "env": {
        "EXPO_PUBLIC_API_URL": "https://api.{{PROJECT_SLUG}}.example.com"
      },
      "ios": {
        "buildConfiguration": "Release"
      }
    }
  },
  "submit": {
    "dev-testflight": {
      "ios": {
        "ascApiKeyPath": "./asc-api-key.p8",
        "groups": ["Development"]
      }
    },
    "production": {
      "ios": {
        "ascApiKeyPath": "./asc-api-key.p8",
        "groups": ["Production"]
      }
    }
  }
}
