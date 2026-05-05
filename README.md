# Docker Valkey-Glide

## Download repo

```sh
git clone https://github.com/adrianluna/docker-valkey-glide.git
```

## Update docker-compose.yml 

You need to update the volumes in the `docker-compose.yml` according to your directory

## Create containers

```sh
cd docker-valkey-glide/
docker-compose up
```

## Enter exec mode on php container

```sh
docker exec -it docker-valkey-glide-php-1 bash
```