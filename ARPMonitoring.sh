#!/bin/bash
# ---------------------------------------------------------------
# ARPMonitoring.sh
# Legge gli eventi di arpwatch e segnala i possibili IP duplicati.
# Necessario installare arpwatch:
#                              Debian: apt install arpwatch
#                              Arch: pacman -S arpwatch
# 
#Uso:
#   ARPMonitoring.sh          modo normale: resta in ascolto
#   ARPMonitoring.sh --test   legge righe di prova dalla pipe
# ---------------------------------------------------------------

LOG_FILE="/var/log/ip-duplicati.log"   # file dove scrivere gli avvisi
PAUSA=300                              # secondi tra due avvisi per lo stesso IP
EMAIL_DESTINATARI=(emailtest@test.com) # array per scrivere piu destinatari

# Memoria dello script: per ogni IP ricorda quando ha avvisato l'ultima volta
declare -A ULTIMO_AVVISO

# Da dove arrivano le righe da analizzare
leggi_eventi() {
    if [[ "$1" == "--test" ]]; then
        cat                                              # righe di prova
    else
        journalctl -f -n 0 -u 'arpwatch@*' -o cat        # eventi reali
    fi
}

# Le righe che ci interessano hanno questa forma:
#   flip flop 192.168.1.50 0:1:2:3:4:5 (a:b:c:d:e:f)
REGEX='^(flip flop|changed ethernet address) ([0-9.]+) ([0-9a-fA-F:]+) \(([0-9a-fA-F:]+)\)'

# Cosa fare quando c'e' un avviso
avvisa() {
    local messaggio="$1"
    local ip="$2"
    echo "$messaggio" >> "$LOG_FILE"                     # 1) scrive nel file
    logger -t ip-duplicati -p user.warning "$messaggio"  # 2) scrive nel journal

    # 3) email, solo se hai indicato un destinatario in alto
    if [[ ${#EMAIL_DESTINATARI[@]} -gt 0  ]]; then
        local corpo="$messaggio"$'\n\n'"Verifica dal server: ip neigh show $ip"
        if ! echo "$corpo" | mail -s "[$(hostname)] Possibile IP duplicato: $ip" "${EMAIL_DESTINATARI[@]}"; then
            echo "$(date '+%F %T') ERRORE: invio email non riuscito" >> "$LOG_FILE"
        fi
    fi
}

# Ciclo principale: legge una riga alla volta, per sempre
leggi_eventi "$1" | while read -r riga; do

    if [[ "$riga" =~ $REGEX ]]; then
        tipo="${BASH_REMATCH[1]}"
        ip="${BASH_REMATCH[2]}"
        mac_nuovo="${BASH_REMATCH[3]}"
        mac_vecchio="${BASH_REMATCH[4]}"

        # Anti-spam: stesso IP avvisato da poco? Salta
        adesso=$(date +%s)
        ultimo=${ULTIMO_AVVISO[$ip]:-0}
        if (( adesso - ultimo < PAUSA )); then
            continue
        fi
        ULTIMO_AVVISO[$ip]=$adesso

        # flip flop = l'IP rimbalza tra due MAC: segnale tipico di duplicato
        if [[ "$tipo" == "flip flop" ]]; then
            livello="PROBABILE DUPLICATO"
        else
            livello="DA VERIFICARE"
        fi

        avvisa "$(date '+%F %T') [$livello] IP $ip: MAC $mac_nuovo (prima: $mac_vecchio) - evento: $tipo" "$ip"
    fi

done
