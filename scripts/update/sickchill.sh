#!/bin/bash
# Update sickrage to sickchill

if [[ -f /install/.sickrage.lock ]]; then
    echo "Updating SickRage to SickChill"
    user=$(cut -d: -f1 < /root/.master.info)
    active=$(systemctl is-active sickrage@$user)
    if [[ $active == 'active' ]]; then
        systemctl disable --now sickrage@$user
    fi
    cd /home/$user
    git clone https://github.com/SickChill/SickChill.git .sickchill
    chown -R $user: .sickchill
    cp -a .sickrage/config.ini .sickchill
    cp -a .sickrage/sickbeard.db .sickchill
    sed -i "s|git_remote_url.*|git_remote_url = https://github.com/SickChill/SickChill.git|g" /home/${master}/.sickchill/config.ini
    echo "Moving ~/.sickrage to ~/sickrage.defunct. You can safely delete this yourself if the upgrade completes successfully."
    mv .sickrage sickrage.defunct
    rm -f /etc/systemd/system/sickrage@.service
    cat > /etc/systemd/system/sickchill@.service <<SSS
[Unit]
Description=SickChill
After=syslog.target network.target

[Service]
Type=forking
GuessMainPID=no
User=%I
Group=%I
ExecStart=/usr/bin/python /home/%I/.sickchill/SickBeard.py -q --daemon --nolaunch --datadir=/home/%I/.sickchill


[Install]
WantedBy=multi-user.target
SSS
    if [[ -f /install/.nginx.lock ]]; then
        rm -f /etc/nginx/apps/sickrage.conf
        cat > /etc/nginx/apps/sickchill.conf <<SRC
location /sickchill {
    include /etc/nginx/snippets/proxy.conf;
    proxy_pass        http://127.0.0.1:8081/sickchill;
    auth_basic "What's the password?";
    auth_basic_user_file /etc/htpasswd.d/htpasswd.${master};
}
SRC
        sed -i "s/web_root.*/web_root = \/sickchill/g" /home/${master}/.sickchill/config.ini
        systemctl reload nginx
    fi
    systemctl daemon-reload
    if [[ $active == 'active' ]]; then
        systemctl start sickchill@$master
    fi
    mv /install/.sickrage.lock /install/.sickchill.lock
fi

if [[ -f /install/.sickchill.lock ]]; then
    if [[ -f /etc/systemd/system/sickchill@.service ]]; then
        user=$(cut -d: -f1 < /root/.master.info)
        active=$(systemctl is-active sickchill@$user)
        codename=$(lsb_release -cs)
        log=/root/logs/swizzin.log

        if [[ $codename =~ ("xenial"|"stretch"|"buster"|"bionic") ]]; then
            LIST='git python2-dev virtualenv python-virtualenv python-pip'
        else
            LIST='git python2-dev'
        fi
        apt-get -y -q update >> $log 2>&1

        for depend in $LIST; do
        apt-get -qq -y install $depend >>"${log}" 2>&1 || { echo "ERROR: APT-GET could not install a required package: ${depend}. That's probably not good..."; }
        done

        if [[ ! $codename =~ ("xenial"|"stretch"|"buster"|"bionic") ]]; then
        . /etc/swizzin/sources/functions/pyenv
        python_getpip
        pip install virtualenv >>"${log}" 2>&1
        fi

        echo "Setting up the SickChill venv ..."
        mkdir -p /home/${user}/.venv
        chown ${user}: /home/${user}/.venv
        python2 -m virtualenv /home/${user}/.venv/sickchill >>"${log}" 2>&1
        chown -R ${user}: /home/${user}/.venv/sickchill

        mv /home/${user}/.sickchill /home/${user}/sickchill

        cat > /etc/systemd/system/sickchill.service <<SCSD
[Unit]
Description=SickChill
After=syslog.target network.target

[Service]
Type=forking
GuessMainPID=no
User=${user}
Group=${user}
ExecStart=/home/${user}/.venv/sickchill/bin/python /home/${user}/sickchill/SickBeard.py -q --daemon --nolaunch --datadir=/home/${user}/sickchill


[Install]
WantedBy=multi-user.target
SCSD
        systemctl daemon-reload

        if [[ $active == "active" ]]; then
            systemctl restart sickchill
        fi
    fi
fi
