import secrets #fornisce numeri casuali sicuri per uso crittografato (si appoggia al generatore de S.O.)
import string #costanti di testo già pronte
import argparse #legge gli argomenti scritti nel terminale

def genera_password(lunghezza=16, simboli=True):
    caratteri = string.ascii_letters + string.digits
    if simboli:
        caratteri += "!@#$%^&*()-_=+[]{};:,.<>?"

    while True:
        password = "".join(secrets.choice(caratteri) for _ in range(lunghezza))
        # Garantisce almeno una minuscola, una maiuscola e un numero
        if (any(c.islower() for c in password)
                and any(c.isupper() for c in password)
                and any(c.isdigit() for c in password)
                and (not simboli or any(c in string.punctuation for c in password))):
            return password

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generatore di password casuali")
    parser.add_argument("-l", "--lunghezza", type=int, default=16, help="lunghezza (default 16)")
    parser.add_argument("-n", "--numero", type=int, default=1, help="quante password generare")
    parser.add_argument("--no-simboli", action="store_true", help="esclude i simboli")
    args = parser.parse_args()

    if args.lunghezza < 8:
        parser.error("la lunghezza minima consigliata è 8")

    for _ in range(args.numero):
        print(genera_password(args.lunghezza, not args.no_simboli))
