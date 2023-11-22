#!/bin/bash

#VARIABLES
HOME='~/'
TEMPDIR='/tmp/tmpdir'
DOCKER_USER=""
DOCKER_TOKEN=""
DOCKER_REPO="dockerproject"

#Colors
RED='\033[0;31m'
NC='\033[0m'






####PACKAGES

#This checks for any docker installation and removes it.
echo "${RED}Removing old Docker packages${NC}"
sudo apt-get purge docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras -y
#Delete images, containers, etc.
sudo rm -rf /var/lib/docker
sudo rm -rf /var/lib/containerd
sudo rm -rf /etc/apt/keyrings/docker.gpg


#Add docker's pgp keys
echo  "${RED}Adding docker's pgp keys ${NC}"
sudo apt-get update 
sudo apt-get install ca-certificates curl gnupg -y
sudo install -m 0755 -d /etc/apt/keyrings 
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

#Add repository
echo "${RED}Adding repository ${NC}"
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update 

#Install Docker
echo "${RED}Installing docker ${NC}"
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

#Install docker-compose
echo "${RED}Installing docker-compose ${NC}"
sudo curl -SL https://github.com/docker/compose/releases/download/v2.23.1/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

#Enable service
echo "${RED}Enabling service ${NC}"
sudo systemctl enable docker


####REPOSITORY
echo "${RED}Cloning respository ${NC}"
if [ -d $TEMPDIR/295words-docker/ ];
then
	echo "Repository already exist"
else
git clone -b ejercicio2-dockeriza https://github.com/roxsross/bootcamp-devops-2023.git  ${TEMPDIR}
fi

##DOCKERFILES
echo "${RED}Creating Dockerfiles ${NC}"

#Api
cat <<EOF > ${TEMPDIR}/295words-docker/api/Dockerfile
FROM amazoncorretto:17
WORKDIR /app
ENV M2_HOME=/opt/apache-maven-3.9.5
COPY . .
RUN yum install wget tar xz gzip ps -y
RUN wget https://dlcdn.apache.org/maven/maven-3/3.9.5/binaries/apache-maven-3.9.5-bin.tar.gz 
RUN tar -xzf apache-maven-3.9.5-bin.tar.gz -C /opt
ENV PATH=\$PATH:\$M2_HOME/bin
RUN echo $PATH
RUN mvn compile
RUN mvn install
CMD ["java","-jar", "/app/target/words.jar"]
EOF

#Web
cat <<EOF > ${TEMPDIR}/295words-docker/web/Dockerfile
FROM golang:latest
WORKDIR /go/src/app
COPY . .
EXPOSE 8080
CMD ["go","run","dispatcher.go"]
EOF

#Db
cat <<EOF > ${TEMPDIR}/295words-docker/db/docker-entrypoint.sh
#!/bin/bash

# Function to check if PostgreSQL is ready
check_postgres() {
  until pg_isready -p 5432 -U postgres; do
    echo "Waiting for PostgreSQL to start..."
    sleep 1
  done
}

# Check if PostgreSQL is ready
check_postgres

# Run SQL commands from the file
psql -U postgres -d "postgres" -a -f /app/words.sql
EOF


cat <<EOF > ${TEMPDIR}/295words-docker/db/Dockerfile
FROM postgres:15-alpine
ENV POSTGRES_USER postgres
ENV POSTGRES_PASSWORD postgres
ENV POSTGRES_DB postgres
WORKDIR /app
COPY ./words.sql /app/words.sql
COPY ./docker-entrypoint.sh /docker-entrypoint-initdb.d/
EXPOSE 5432
EOF


#Logueo a dockerhub
echo "$DOCKER_TOKEN" | sudo docker login --username "$DOCKER_USER" --password-stdin



#Funciona para hacer build,tag y push de cada container.
function build(){
	local containers=("web" "db" "api")
  for container in "${containers[@]}"; do
    cd ${TEMPDIR}/295words-docker/"$container"/
    sudo docker build -t "$container"-image .
    sudo docker tag "$container"-image "$DOCKER_USER"/"$DOCKER_REPO":$container
    sudo docker push "$DOCKER_USER"/"$DOCKER_REPO":$container
  done
}

#Ejecuto funcion
build

#Genero docker-compose.yaml

cat <<EOF > docker-compose.yml
version: '3'

services:
  api:
    image: luke8815/dockerproject:api
    networks:
      - red1

  db:
    image: luke8815/dockerproject:db
    expose:
      - "5432:5432"
    networks:
      - red1

  web:
    image: luke8815/dockerproject:web
    expose:
      - "80:80"
    networks:
      - red1

networks:
  red1:
    driver: bridge
EOF