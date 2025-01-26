Скрипт автоматического создания домена, проекта в домене и пользователей в проекте для "Кибер инфраструктура"

Для работы нужно: 

    1. Скачать файлы, сделать скрипт исполняемым
    2. Заполнить файлы users.txt и vars.conf (Так же можно просто создать любые)
    3. При необходимости - в самом скрипте ci_user_mgmt.sh изменить значение переменной $INSECURE на нулевое, что бы openstack cli проверял сертификат сервера
    4. Запустить скрипт

Функции скрипта:

    1. ci_user_mgmt.sh create - Создать пользователей
    2. ci_user_mgmt.sh delete-resource - Удалить созданные вм и их диски для пользователей
    3. ci_user_mgmt.sh delete-all - Удалить всё созданное пользователями, проект и домен 


Синтаксис:

    1. ci_user_mgmt.sh create <user_file> <vars_file>
    2. ci_user_mgmt.sh delete-resources <username|user_file>
    3. ci_user_mgmt.sh delete-all <username|user_file> <vars_file>
    
На данный момент скрипт не удаляет loadbalancer и k8s кластеры (Их можно удалить из админки руками)
