#!/bin/bash
INSECURE="--insecure"
if ! command -v openstack &> /dev/null; then
    echo "Ошибка: OpenStack CLI не установлен!"
    exit 1
fi


create_users() {
    user_file="$1"
    vars_file="$2"

    #Создаём домен, если он не существует
    if [ -n $(openstack domain show domain_name $INSECURE | grep "No domain") ]; then
        openstack domain create "$domain_name" $INSECURE
    fi

    #Создаем проект
    if [ -n $(openstack project show "$project_name" --domain "$domain_name" $INSECURE | grep "No project" ) ]; then
        openstack project create "$project_name" --domain "$domain_name" $INSECURE
    fi

    #Читаем файл с логинами и паролями
    while IFS= read -r line; do
        username=$(echo "$line" | cut -d':' -f1)
        password=$(echo "$line" | cut -d':' -f2)

        if [ -n $(openstack user show "$username" --domain "$domain_name" $INSECURE | grep "No user") ]; then
            openstack user create "$username" --password "$password" --domain "$domain_name" $INSECURE
            sleep 5
            user_id=$(openstack user show "$username" --domain "$domain_name" -c id -f value $INSECURE)
            openstack role add --user "$user_id" --project "$project_name" admin $INSECURE
            echo "Пользователь $username создан."
        else
            echo "Пользователь $username уже существует."
        fi
    done < "$user_file"

    #Применяем лимиты
    openstack quota set --cores "$CORES_LIMIT" --ram "$RAM_LIMIT" --gigabytes "$GIGABUTES_LIMIT" --floating-ips "$FLOATING_IPS_LIMIT" "$project_name" $INSECURE
    echo "Лимиты установлены --cores $CORES_LIMIT --ram $RAM_LIMIT --gigabytes $GIGABUTES_LIMIT --floating-ips $FLOATING_IPS_LIMIT в $project_name"
}

#Удаление ресурсов пользователя
delete_user_resources() {
    username="$1"
    user_id=$(openstack user show "$username" --domain "$domain_name" -c id -f value $INSECURE 2>/dev/null)
    if [[ -z "$user_id" ]]; then
        echo "Пользователь $username не существует."
        return
    fi
     echo "Удаление ресурсов пользователя $username..."
    sleep 5
    #Удаление VMs
    for id in $(openstack server list --user $user_id --all-projects -c ID -f value $INSECURE ); do
        openstack server delete "$id" $INSECURE
        echo "Удалён сервер: $id"
    done

    sleep 5
    # Удаляем диски (volumes)
    for id in $(openstack volume list --user $user_id --all-projects -c ID -f value $INSECURE ); do
        openstack volume delete "$id" $INSECURE
        echo "Удалён диск: $id"
    done


    echo "Все ресурсы пользователя $username удалены."
}

#Удаление всех ресурсов пользователей взятых из файла
delete_user_resources_from_file() {
    user_file="$1"
    while IFS= read -r line; do
        username=$(echo "$line" | cut -d':' -f1)
        delete_user_resources "$username"
    done < "$user_file"
}

#Удаление пользователей вместе с их ресурсами
delete_user_and_resources() {
    username="$1"
    delete_user_resources "$username"

    # Удаляем floating IP
    sleep 5
    for id in $(openstack floating ip list --project "$project_name" -c ID -f value $INSECURE); do
        openstack floating ip delete "$id" $INSECURE
        echo "Удалён floating IP: $id"
    done

    #Отсоединение портов от роутеров
    sleep 5
    for id in $(openstack router list --project "$project_name" -c ID -f value $INSECURE); do
        openstack router set "$id" --disable $INSECURE
        local router_port=$(openstack router show $id -c interfaces_info -f value $INSECURE | awk -F'"port_id": "' '{for (i=2; i<=NF; i++) print $i}' | cut -d'"' -f1)
        for port in $router_port; do
            openstack router remove port $id $port $INSECURE
            echo "Порт $port отсоединен от роутера $id"
        done
    done

    #Удаляем порты
    sleep 5
    for id in $(openstack port list --project "$project_name" -c ID -f value $INSECURE); do
        openstack port delete "$id" $INSECURE 2> /dev/null
        echo "Порт удален: $id"
    done

    #Удаляем маршрутизаторы
    sleep 5
    for id in $(openstack router list --project "$project_name" -c ID -f value $INSECURE); do
        openstack router delete "$id" $INSECURE
        echo "Удалён маршрутизатор: $id"
    done

    #Удаляем подсети
    sleep 5
    for id in $(openstack subnet list --project "$project_name" -c ID -f value $INSECURE); do
        openstack subnet delete "$id" $INSECURE
        echo "Удалена сеть: $id"
    done

    #Удаляем сети
    sleep 5
    for id in $(openstack network list --project "$project_name" -c ID -f value $INSECURE); do
        openstack network delete "$id" $INSECURE
        echo "Удалена сеть: $id"
    done

    openstack user delete "$username" $INSECURE
    echo "Пользователь $username удалён."
    openstack project delete "$project_name" --domain "$domain_name" $INSECURE
    echo "Проект $project_name удалён."
    openstack domain set --disable "$domain_name" $INSECURE
    sleep 2
    openstack domain delete "$domain_name" $INSECURE
    echo "Домен $domain_name удалён."
}

#Удаление пользователей вместе с их ресурсами из файла
delete_users_and_resources_from_file() {
    local user_file="$1"
    while IFS= read -r line; do
        local username=$(echo "$line" | cut -d':' -f1)
        delete_user_and_resources "$username"
    done < "$user_file"
}


case "$1" in
    create)
      #Экспорт переменных
      vars_file=$3
      source $vars_file

        if [[ -z "$2" || -z "$3" ]]; then
            echo "Использование: $0 create <user_file> <vars_file>"
            exit 1
        fi
        create_users "$2"
        ;;
    delete-resources)
      #Экспорт переменных
      vars_file=$3
      source $vars_file

        if [[ -z "$2" || -z "$3" ]]; then
            echo "Использование: $0 delete-resources <username|user_file> <vars_file>."
            exit 1
        fi
        if [[ -f "$2" ]]; then
            delete_user_resources_from_file "$2"
        else
            delete_user_resources "$2"
        fi
        ;;
    delete-all)
      #Экспорт переменных
      vars_file=$3
      source $vars_file

        if [[ -z "$2" || -z "$3" ]]; then
            echo "Использование: $0 delete-all <username|user_file> <vars_file>. Так же удалиться домен и заданный проект в нем!"
            exit 1
        fi
        if [[ -f "$2" ]]; then
            delete_users_and_resources_from_file "$2"
        else
            delete_user_and_resources "$2"
        fi
        ;;
    *)
        echo "Использование: $0 {create|delete-resources|delete-all}"
        exit 1
        ;;
esac