To start the docker network
docker compose -f docker-compose.devops.yml up -d --build

Inspect the network
docker network ls
docker network inspect spring-petclinic-team9_petclinic-devops-net
docker ps

get jenkins admin password
docker exec petclinic-jenkins cat /var/jenkins_home/secrets/initialAdminPassword