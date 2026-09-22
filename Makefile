# Define the path to the Docker Compose configuration file.
COMPOSE_FILE := srcs/docker-compose.yml

# Define the path to the environment variables file.
ENV_FILE := srcs/.env

# Load the variables from srcs/.env into the Makefile.
include $(ENV_FILE)

# Define the complete Docker Compose command used by every target.
COMPOSE := sudo docker compose -f $(COMPOSE_FILE) --env-file $(ENV_FILE)

# Define the persistent directories required by MariaDB and WordPress.
DATA_DIRS := $(DATA_PATH)/mariadb $(DATA_PATH)/wordpress

# Declare targets that do not represent files.
.PHONY: all prepare build up down start stop restart status logs clean fclean re

# Use "up" as the default target when make is executed without arguments.
all: up

# Validate DATA_PATH and create the persistent data directories.
prepare:
	@case "$(DATA_PATH)" in /home/*/data) ;; *) echo "Error: invalid DATA_PATH: $(DATA_PATH)"; exit 1 ;; esac
	sudo mkdir -p $(DATA_DIRS)

# Build all Docker images without starting the containers.
build: prepare
	$(COMPOSE) build

# Build the images and start the complete infrastructure in the background.
up: prepare
	$(COMPOSE) up -d --build

# Stop and remove the containers and network, preserving images and volumes.
down:
	$(COMPOSE) down --remove-orphans

# Start containers that already exist and are currently stopped.
start:
	$(COMPOSE) start

# Stop the running containers without removing them.
stop:
	$(COMPOSE) stop

# Restart all existing containers.
restart:
	$(COMPOSE) restart

# Display the current state of the Compose services.
status:
	$(COMPOSE) ps

# Follow the logs produced by all services.
logs:
	$(COMPOSE) logs -f

# Remove containers and the Compose network, preserving persistent data.
clean:
	$(COMPOSE) down --remove-orphans

# Remove containers, images, volumes and persistent project data.
fclean:
	$(COMPOSE) down --rmi all --volumes --remove-orphans
	@case "$(DATA_PATH)" in /home/*/data) ;; *) echo "Error: refusing to remove invalid DATA_PATH: $(DATA_PATH)"; exit 1 ;; esac
	sudo rm -rf "$(DATA_PATH)/mariadb" "$(DATA_PATH)/wordpress"

# Completely clean the project and rebuild it from the beginning.
re: fclean
	$(MAKE) all
