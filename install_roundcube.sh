#!/bin/bash

# Simple ASCII art pattern for a cloud
echo "#############################################################"
echo "############### Nextcloud Installation #####################"
echo "#############################################################"
echo ""

# Function to prompt for the master password and confirm it
function prompt_password {
    echo "Press Ctrl + C to exit."
    echo "Please enter the master password (minimum 8 characters):"
    read -s MASTER_PASSWORD

    # Check if the password is at least 8 characters long
    if [ ${#MASTER_PASSWORD} -lt 8 ]; then
        echo "Password must be at least 8 characters long. Please try again."
        return 1
    fi

    echo "Please confirm the master password:"
    read -s MASTER_PASSWORD_CONFIRM

    if [ "$MASTER_PASSWORD" != "$MASTER_PASSWORD_CONFIRM" ]; then
        echo "Passwords do not match. Please try again."
        return 1
    fi

    echo "The master password has been successfully recorded."
    return 0
}

# Loop until the passwords match and meet the length requirement
while ! prompt_password; do
    # Passwords do not match or are too short; prompt again
    echo "Please re-enter your password."
done

# Continue with the installation process
echo "Proceeding with Nextcloud installation..."

# Update the package list
echo "Updating package list..."

#installier alle pakete
sudo apt install apache2 mysql-server php php-mysql php-pear php-net-smtp php-mail-mime php-mbstring php-xml php-json php-curl -y

databaseUser='roundcube'

cat <<EOF > create-roundcube-db.sql
CREATE DATABASE roundcube;
CREATE USER '$databaseUser'@'localhost' IDENTIFIED BY '$MASTER_PASSWORD';
GRANT ALL PRIVILEGES ON roundcube.* TO '$databaseUser'@'localhost';
FLUSH PRIVILEGES;
EOF

sudo mysql -u root < create-roundcube-db.sql




sudo debconf-set-selections <<< "roundcube-core roundcube/dbconfig-install boolean false"
sudo debconf-set-selections <<< "roundcube-core roundcube/database-type select none"

sudo apt install roundcube roundcube-core -y



# Datei Pfad
file_path="/etc/roundcube/config.inc.php"

# Überprüfen, ob die Datei existiert
if [ -f "$file_path" ]; then
    # Suchen und auskommentieren der Zeile, die mit $config['db_dsnw'] beginnt
    sudo sed -i '/^\s*\$config\['\''db_dsnw'\''\] =/s/^/#/' "$file_path"
fi


# Überprüfen, ob die Datei existiert
if [ -f "$file_path" ]; then
   
    # Suchen und auskommentieren der Zeile, die mit $config['enable_installer'] beginnt
    sudo sed -i '/^\s*\$config\['\''enable_installer'\''\] =/s/^/#/' "$file_path"
fi



# Datei Pfad
config_file="/etc/roundcube/config.inc.php"

# Überprüfen, ob die Datei existiert
if [ -f "$config_file" ]; then
    # Füge die neue Zeile für die Datenbankverbindung hinzu
    {
        echo "\$config['db_dsnw'] = 'mysql://$databaseUser:$MASTER_PASSWORD@localhost/roundcube';"
        echo "\$config['enable_installer'] = true;"
    } | sudo tee -a "$config_file" > /dev/null
else
    echo "Die Datei $config_file existiert nicht."
fi

# Datei Pfad
config_file="/etc/apache2/sites-available/000-default.conf"

# Überprüfen, ob die Datei existiert
if [ -f "$config_file" ]; then
    # Datei löschen, falls sie existiert
    sudo rm "$config_file"
fi

# Erstellen der Datei mit dem neuen Inhalt
sudo tee "$config_file" > /dev/null <<EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /usr/share/roundcube
    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

# Pfad zur Konfigurationsdatei
conf_file="/etc/apache2/conf-available/roundcube.conf"

# Überprüfen, ob die Konfigurationsdatei existiert
if [ -f "$conf_file" ]; then
    # Konfigurationsdatei löschen, falls sie existiert
    sudo rm "$conf_file"
fi

# Neue Konfigurationsdatei erstellen
sudo tee "$conf_file" > /dev/null <<EOF
# Those aliases do not work properly with several hosts on your apache server
# Uncomment them to use it or adapt them to your configuration
#    Alias /roundcube /var/lib/roundcube/public_html

<Directory /var/lib/roundcube/public_html/>
  Options +FollowSymLinks
  # This is needed to parse /var/lib/roundcube/.htaccess. See its
  # content before setting AllowOverride to None.
  AllowOverride All
  <IfVersion >= 2.3>
    Require all granted
  </IfVersion>
  <IfVersion < 2.3>
    Order allow,deny
    Allow from all
  </IfVersion>
</Directory>

# Protecting basic directories (not needed when the document root is
# /var/lib/roundcube/public_html):
<Directory /var/lib/roundcube/config>
  Options -FollowSymLinks
  AllowOverride None
</Directory>

<Directory /var/lib/roundcube/temp>
  Options -FollowSymLinks
  AllowOverride None
  <IfVersion >= 2.3>
    Require all denied
  </IfVersion>
  <IfVersion < 2.3>
    Order allow,deny
    Deny from all
  </IfVersion>
</Directory>

<Directory /var/lib/roundcube/logs>
  Options -FollowSymLinks
  AllowOverride None
  <IfVersion >= 2.3>
    Require all denied
  </IfVersion>
  <IfVersion < 2.3>
    Order allow,deny
    Deny from all
  </IfVersion>
</Directory>

EOF
sudo mysql -u root roundcube < /usr/share/roundcube/SQL/mysql.initial.sql
# Aktivieren der neuen Konfiguration
sudo a2enconf roundcube
# Sicherstellen, dass die 000-default.conf aktiviert ist
sudo a2ensite 000-default.conf

# Apache-Webserver neu starten
sudo systemctl restart apache2

sudo chown www-data:www-data /etc/roundcube/config.inc.php
sudo chmod 640 /etc/roundcube/config.inc.php

# IP-Adresse herausfinden und in die Variable speichern
ip_address=$(hostname -I | awk '{print $1}')

# Falls hostname -I nicht funktioniert, kannst du alternative Methoden verwenden:
# ip_address=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

# Überprüfen, ob die IP-Adresse erfolgreich gesetzt wurde
if [ -z "$ip_address" ]; then
    echo "Fehler: IP-Adresse konnte nicht ermittelt werden."
    exit 1
fi

# Ausgabe der Links mit der richtigen IP-Adresse
echo "###################################################################"
echo "Login Link http://$ip_address"
echo "Configuration Link http://$ip_address/installer"
echo "###################################################################"
