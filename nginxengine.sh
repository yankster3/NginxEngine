#!/bin/bash
#Varibles 
FLAG1=0								# FLAG1 to check whether nginx and mysql is installed						
phpupgrade=0						#To check whether php is installed and its 5.4
#these flags will help to install only uninstalled packages 
#also package management will be called minimum times speeding up the whole setup

function print_info {
    echo -n -e '\e[1;36m'
    echo -ne $1
    echo -e '\e[0m'
 }

#Sanity check: suggested run as sudoer
FILE="/tmp/out.$$"
GREP="/bin/grep"

if [ "$(id -u)" = "0" ]; then
   print_info "\vScript is being run as root.\nIt will run under root but suggested to run as user for security.\nGO SUDO!!!."
   else
   print_info "\vScript is run as a normal user.\nwhich will generate a normal alert During nginx installation. \nPlease Ignore the alert and let Script run" 		
fi
sleep 2


dpkg -s nginx > /dev/null  2>&1 && {
        print_info "nginx is installed." 
		nginx=""
 } || {
        print_info "nginx will be installed."
		nginx=nginx
		FLAG1=1
	
      }
dpkg -s mysql-server > /dev/null  2>&1 && {
        print_info "mysql is installed." 
   	mysql=""
 } || {
        print_info "mysql will be installed."
 	mysql="mysql-server mysql-client"
	FLAG1=2
    }

php -v > /dev/null  2>&1 && {
        print_info "php is installed." 
        version=$(dpkg -s php5-common | grep -i version | cut -c 10-12)
        echo $version
        test "$version" == "5.4" && upgradephp=2 || upgradephp=1
        echo $upgradephp
        
   	 } || {
        print_info "php will be installed."
 		upgradephp=1
    }
    
    case "$FLAG1" in
	1|2) sudo apt-get install nginx $mysql curl unzip 	;;
esac	
sudo /etc/init.d/nginx start 
	print_info "nginx started"
	
#Enquirying for FQDN and updating hosts file
	
IP=`ifconfig  | grep 'inet addr:'| grep -v '127.0.0.1' | cut -d: -f2 | awk '{ print $1}'`
read -p "Enter the hostname (FQDN)"  NAME
echo "$IP $NAME" | sudo tee -a /etc/hosts	
	
#Setting VirtualHost
sudo mkdir -p /var/www/$NAME/web
sudo mkdir -p /var/www/$NAME/log

#Setting up logfiles
sudo ln -s /var/log/nginx/$NAME.access.log /var/www/$NAME/log/access.log
sudo ln -s /var/log/nginx/$NAME.error.log /var/www/$NAME/log/error.log

# Modifying Directory Permissions to store files
sudo usermod -a -G www-data $USER
sudo chown -R www-data:www-data /var/www
sudo chmod -R 775 /var/www

#feeding in Configuration from the template
NEWNAME=$NAME
TNAME=$(echo "$NAME" | sed 's/www.//')
sudo cp hostconf "/etc/nginx/sites-available/$NAME" 
sudo sed -i "s:www.example.com:$NAME:g" "/etc/nginx/sites-available/$NAME" 
sudo sed -i "s:example.com:$TNAME:" "/etc/nginx/sites-available/$NAME"

#Enable sites and configure nginx
sudo ln -s "/etc/nginx/sites-available/$NAME" "/etc/nginx/sites-enabled/$NAME"
sudo /etc/init.d/nginx restart #2>&1 && { echo "nginx is restarted." } || { echo "retrying to restart" sudo fuser -k 80/tcp sudo /etc/init.d/nginx restart  }


#php installation and configuration
if [ $upgradephp = 1 ] ; 
then 
	print_info "Downloading Packages from Launchpad repo"
	sudo apt-get install python-software-properties
	sudo add-apt-repository ppa:ondrej/php5
	sudo apt-get update
	sudo apt-get install php5-cli php5-common php5-mysql
fi
sudo apt-get install php5-fpm php5-cgi php-apc #these packages are essentially neded for our setup
sudo service php5-fpm start

sudo touch /var/www/$NAME/web/info.php
echo "<?php
phpinfo();
?>" | sudo tee /var/www/$NAME/web/info.php
#clear
print_info "\n php has been setup. verify at $NAME/info.php"
print_info "\n Configuring php-fpm to handle phpcgi"


<<COMMEN1 
Snippet needed if script needs to be deeloped to install with php < 5.4

sudo sed -i 's;listen = 127.0.0.1:9000;listen = /tmp/php5-fpm.sock;' /etc/php5/fpm/pool.d/www.conf
processid=$(sudo netstat -tpan |grep "LISTEN"|grep :9000|cut -d: -f3|awk '{ print $3}'| tr -d [=php5= | tr -cd [:digit:])
echo $processid
sudo kill "$processid"
sudo /usr/bin/spawn-fcgi -a 127.0.0.1 -p 9000 -u www-data -g www-data -f /usr/bin/php5-cgi -P /var/run/fastcgi-php.pid
echo "1"
COMMEN1

#Downloading and Setting up Wordpress Files
cd /tmp
print_info "\n Downloading Latest wordpress. Please wait"
wget -c http://wordpress.org/latest.zip
print_info "\n Done. Unzipping wordpress"
unzip -qq latest.zip 
print_info "Setting wordpress files"
sudo cp -r /tmp/wordpress/* "/var/www/$NAME/web"

#To support mysql naming conentions replacing . with _
echo $NAME > test
sed -i 's/\./\_/g' test
DBNAME=`cat test`

#Start mysql server
print_info "\nStarting mysql server"
sudo service mysql start

#setting root password in mysql 
print_info  "\nSetting password in mysql for root user"
sudo mysqladmin -u root password 'admin'

#Create database

print_info "\vCreating Database"
sudo mysqladmin -h localhost -u root -padmin create $DBNAME\_db


sudo cp "/var/www/$NAME/web/wp-config-sample.php" "/var/www/$NAME/web/wp-config.php"

#Editing wp-config.php for mysql connectivity
sudo sed -i 's:database_name_here:'$DBNAME'_db:; s:username_here:root:; s:password_here:admin:' "/var/www/$NAME/web/wp-config.php"

#Removing files from /tmp directory
print_info "\nRemoving temporary file"
rm -rf /tmp/latest.zip
rm -rf /tmp/wordpress/
sudo /etc/init.d/nginx restart

print_info "\nsetup completed. Point browser to $NAME"
print_info "$NAME/info.php to see php information"
#END
