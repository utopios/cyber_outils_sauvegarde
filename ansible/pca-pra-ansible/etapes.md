
## Etape 0

- Inventaire:
    - Adresse IP de la machine DC Paris
    - Adresse IP de la macine DC Lyon


## Etape 1

- PlayBook pour déployer les applications dans chaque datacenter.
    - Module pour installer docker dans chaque datacenter
    - Module copy des docker compose 
    - Module commande pour executer les docker compose 

## Etape 2

- Playbook sauvegarde 
    - Module commande pour executer la commande de sauvegarde.
        cmd: docker exec -it <Commande pour générer un backup>
    - Module copy la sauvegarde dans l'agent.
        cpy:
            src: <sur la machine du datacenter>
            destination: <sur l'agent>
    - Module pour tester la sauvegarde dans le DC Lyon.

