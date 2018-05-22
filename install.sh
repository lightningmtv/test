#!/bin/bash
echo "####################################################"
echo "#        Pterodactyl Auto Installer Script         #"
echo "#    This version installs the Panel and Daemon!   #"
echo "#   We just need a few things before we can start  #"
echo "####################################################"
echo ""
read -p 'Web URL [!!!WITHOUT!!! HTTP//HTTPS!] (E.g: panel.domain.com)' url
read -p 'Timezone (E.g: UTC)' timezone
read -p 'Egg Author Email (E.g: panel@domain.com)' eggemail
read -p 'Admin Account Email (E.g: you@domain.com)' adminemail
read -p 'Admin Account Username (E.g: JohnDoe)' adminusername
read -p 'Admin Account First Name (E.g: John)' adminfirstname
read -p 'Admin Account Last Name (E.g: Doe)' adminlastname
echo ""
echo ""
echo "##########################################"
echo "#          Updating apt packages         #"
echo "##########################################"
sudo apt -y autoremove
sudo apt -y install software-properties-common
sudo add-apt-repository -y ppa:ondrej/php
sudo add-apt-repository -y ppa:chris-lea/redis-server
sudo apt-get -y update
echo "##########################################"
echo "#    Panel Installation is starting..    #"
echo "#     Installing server requirements     #"
echo "##########################################"
sudo apt-get -y install php7.2 php7.2-cli php7.2-gd php7.2-mysql php7.2-pdo php7.2-mbstring php7.2-tokenizer php7.2-bcmath php7.2-xml php7.2-fpm php7.2-curl php7.2-zip mariadb-server nginx curl tar unzip git redis-server mariadb-server
echo "##########################################"
echo "#       Creating panel directory..       #"
echo "##########################################"
mkdir -p /var/www/html/pterodactyl
cd /var/www/html/pterodactyl
echo "##########################################"
echo "#     Downloading & Installing panel..   #"
echo "##########################################"
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/download/v0.7.6/panel.tar.gz
tar --strip-components=1 -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache
curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
export MySQLRootPass=`cat /dev/urandom | tr -dc A-Za-z0-9 | dd bs=25 count=1 2>/dev/null`
export MySQLPterodacPass=`cat /dev/urandom | tr -dc A-Za-z0-9 | dd bs=25 count=1 2>/dev/null`
export AdminAccountPass=`cat /dev/urandom | tr -dc A-Za-z0-9 | dd bs=25 count=1 2>/dev/null`
/sbin/service mysql start
service mysql start
sudo mysql -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${MySQLRootPass}');"
sudo mysql -e "CREATE DATABASE pterodactyl;"
sudo mysql -e "GRANT ALL ON pterodactyl.* to pterodactyl@127.0.0.1 IDENTIFIED BY '${MySQLPterodacPass}';"
sudo mysql -e "FLUSH PRIVILEGES;"
cp .env.example .env
composer install --no-dev
php artisan key:generate --force
php artisan p:environment:setup --url=https://$url --timezone=$timezone --session=database --cache=file --author=$eggemail --queue=database --disable-settings-ui
php artisan p:environment:database --host=127.0.0.1 --port=3306 --database=pterodactyl --username=pterodactyl --password=$MySQLPterodacPass
php artisan migrate --force
php artisan db:seed --force
php artisan p:user:make --email=$adminemail --username=$adminusername --name-first=$adminfirstname --name-last=$adminlastname --password=$AdminAccountPass --admin=1
chown -R www-data:www-data *
(crontab -l 2>/dev/null; echo "* * * * * php /var/www/pterodactyl/html/artisan schedule:run >> /dev/null 2>&1") | crontab -
sudo service cron restart
cat <<EOF >/etc/systemd/system/pteroq.service
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
# On some systems the user and group might be different.
# Some systems use `apache` as the user and group.
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/html/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl enable pteroq.service
sudo systemctl start pteroq
wget https://raw.githubusercontent.com/Tom7653/Pter-Nginx-Config-/master/pterodactyl.conf -P /etc/nginx/sites-available/
sed -i "s/<domain>/$url/g" /etc/nginx/sites-available/pterodactyl.conf
sudo ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
service nginx restart
echo "##########################################"
echo "#            Setting up SSL..            #"
echo "##########################################"
service nginx stop
sudo apt-get install -y letsencrypt
letsencrypt certonly -d $url
service nginx start
echo "##################################################"
echo "#  Panel install complete. Now installing daemon #"
echo "##################################################"
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"
sudo apt-get -y update
sudo apt-get -y install docker-ce
systemctl enable docker
curl -sL https://deb.nodesource.com/setup_8.x | sudo -E bash -
apt -y install nodejs
apt -y install tar unzip make gcc g++ python
echo "##################################################"
echo "#            Creating daemon directory           #"
echo "##################################################"
mkdir -p /srv/daemon /srv/daemon-data
cd /srv/daemon
echo "##################################################"
echo "#            Downloading daemon files            #"
echo "##################################################"
curl -Lo daemon.tar.gz https://github.com/pterodactyl/daemon/releases/download/v0.5.4/daemon.tar.gz
tar --strip-components=1 -xzvf daemon.tar.gz
npm install --only=production
cat <<EOF >/etc/systemd/system/wings.service
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service

[Service]
User=root
#Group=some_group
WorkingDirectory=/srv/daemon
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/bin/node /srv/daemon/src/index.js
Restart=on-failure
StartLimitInterval=300

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable wings
systemctl start wings
clear
echo "##################################################"
echo "#                  Panel setup!                  #"
echo "#           !!PLEASE READ BELOW BELOW!!          #"
echo "##################################################"
echo "Admin Account Username: $adminusername"
echo "Admin Account Password: $AdminAccountPass"
echo "Admin Account Email: $adminemail"
echo "Control Panel URL: https://$url"
echo ""
echo ""
echo "MySQL Root Password: $MySQLRootPass"
echo "MySQL Pterodactyl Password: $MySQLPterodacPass"
echo ""
echo ""
echo "Please save these logins as they are not saved for security reasons"
echo ""
echo ""
echo "!!IMPORTANT!!"
echo "!!IMPORTANT!!"
echo "!!IMPORTANT!!"
echo "You must now add the node to the panel, as this cannot be automated. This is very simple."
echo "Step 1) Login to your panel and enter the admin panel by clicking the gears button in the top right"
echo "Step 2) Create a location by clicking Locations on the left panel then Create New in the top right"
echo "Step 3) After you have created your location, go to nodes. You can find this on the left panel"
echo "Step 4) Click create new in the top right and fill out the info. Then click create node"
echo "Step 5) Click Configuration on the top tab then generate a token using the Auto-Deploy button"
echo "Step 6) Type -cd /srv/daemon/config/- in SSH (here) and paste the command you just copied from the panel"
echo "Your panel should now be setup. Contact me on MC-Market if you require any other assistance https://www.mc-market.org/members/3515/"
echo ""
echo ""
echo "To start restart the daemon you can use 'Service wings restart'"
echo "To start stop the daemon you can use 'Service wings stop'"
echo "To start start the daemon you can use 'Service wings start'"
echo "Please note the daemon has automatically been started!"
