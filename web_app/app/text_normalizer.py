from __future__ import annotations

import re


WORD_OVERRIDES = {
    "AKT": "АКТ",
    "AKTER": "АКТЕР",
    "AKTERA": "АКТЕРА",
    "ALKOGOLEM": "АЛКОГОЛЕМ",
    "ANNA": "АННА",
    "ANNOI": "АННОЙ",
    "BEGLII": "БЕГЛЫЙ",
    "BEITE": "БЕЙТЕ",
    "BI": "БЫ",
    "BIT": "БИТЬ",
    "BOISHSYA": "БОИШЬСЯ",
    "BYBNOV": "БУБНОВ",
    "CHEM": "ЧЕМ",
    "CHO": "ЧО",
    "DA": "ДА",
    "DEDYSHKA": "ДЕДУШКА",
    "GOLYBCHIKY": "ГОЛУБЧИКИ",
    "GRIB": "ГРИБ",
    "I": "И",
    "IDEM": "ИДЕМ",
    "IDYT": "ИДУТ",
    "IMYA": "ИМЯ",
    "ISPORCHENNOGO": "ИСПОРЧЕННОГО",
    "IZ": "ИЗ",
    "K": "К",
    "KAKOI": "КАКОЙ",
    "KALYAN": "КАЛЬЯН",
    "KAPSULU": "КАПСУЛУ",
    "KAPSULE": "КАПСУЛЕ",
    "KAPSYLE": "КАПСУЛЕ",
    "KAPSYLI": "КАПСУЛЕ",
    "KAPSYLY": "КАПСУЛУ",
    "KLESH": "КЛЕЩ",
    "KOLI": "КОЛИ",
    "KOLYASKA": "КОЛЯСКА",
    "KOLYASKE": "КОЛЯСКЕ",
    "KOLYASKU": "КОЛЯСКУ",
    "KOLYASKY": "КОЛЯСКУ",
    "KOSTILEVA": "КОСТЫЛЕВА",
    "KRUTYAT": "КРУТЯТ",
    "LI": "ЛИ",
    "LUBIT": "ЛЮБИТ",
    "LUKA": "ЛУКА",
    "LYBLY": "ЛЮБЛЮ",
    "LYKA": "ЛУКА",
    "MENEYA": "МЕНЯ",
    "MENYA": "МЕНЯ",
    "MISHA": "МИША",
    "MNE": "МНЕ",
    "MNOI": "МНОЙ",
    "MNOGO": "МНОГО",
    "MOGU": "МОГУ",
    "MOJET": "МОЖЕТ",
    "MOLIS": "МОЛИСЬ",
    "MUZ": "МУЗ",
    "MUZUKE": "МУЗЫКЕ",
    "MYAGOK": "МЯГОК",
    "MYALI": "МЯЛИ",
    "NA": "НА",
    "NADO": "НАДО",
    "NASTYA": "НАСТЯ",
    "NE": "НЕ",
    "NET": "НЕТ",
    "NI": "НЕ",
    "NICHEGO": "НИЧЕГО",
    "NU": "НУ",
    "ON": "ОН",
    "OTKRILSYA": "ОТКРЫЛСЯ",
    "OTKRITIE": "ОТКРЫТИЕ",
    "OTKRIVAET": "ОТКРЫВАЕТ",
    "OTRAVLEN": "ОТРАВЛЕН",
    "OTTOGO": "ОТТОГО",
    "OTVARI": "ОТВАРИ",
    "PEPEL": "ПЕПЕЛ",
    "PIT": "ПИТЬ",
    "PODINMAETSYA": "ПОДНИМАЕТСЯ",
    "PODNIMAETSYA": "ПОДНИМАЕТСЯ",
    "PODNYALSYA": "ПОДНЯЛСЯ",
    "PODNS": "ПОДНОС",
    "PODOSHEL": "ПОДОШЕЛ",
    "PO": "ПО",
    "PODEHALA": "ПОДЪЕХАЛА",
    "POGANII": "ПОГАНЫЙ",
    "POGOVORI": "ПОГОВОРИ",
    "POIDY": "ПОЙДУ",
    "POKLON": "ПОКЛОН",
    "POMOLIS": "ПОМОЛИСЬ",
    "POMOSHI": "ПОМОЩИ",
    "POSLE": "ПОСЛЕ",
    "POSTAVILI": "ПОСТАВИЛИ",
    "POTERYALA": "ПОТЕРЯЛА",
    "POVERNULSYA": "ПОВЕРНУЛСЯ",
    "PRISTANISHYA": "ПРИСТАНИЩА",
    "PUSK": "ПУСК",
    "SAKSOFON": "САКСОФОН",
    "SAM": "САМ",
    "SATIN": "САТИН",
    "SKAJY": "СКАЖУ",
    "S": "С",
    "SHTORKY": "ШТОРКУ",
    "SLEVA": "СЛЕВА",
    "SO": "СО",
    "STENE": "СТЕНЕ",
    "STOLU": "СТОЛУ",
    "STOLY": "СТОЛУ",
    "SVADEBKY": "СВАДЕБКУ",
    "SVISTU": "СВИСТУ",
    "TATARIN": "ТАТАРИН",
    "TEBE": "ТЕБЕ",
    "TEXST": "ТЕКСТ",
    "TI": "ТЫ",
    "TITROV": "ТИТРОВ",
    "TO": "ТО",
    "TURMU": "ТЮРЬМУ",
    "UBEJAL": "УБЕЖАЛ",
    "UITI": "УЙТИ",
    "V": "В",
    "VASELISA": "ВАСИЛИСА",
    "VASKY": "ВАСЬКУ",
    "VIHOD": "ВЫХОД",
    "VIHODOM": "ВЫХОДОМ",
    "VIKATILAS": "ВЫКАТИЛАСЬ",
    "VORA": "ВОРА",
    "VPEDNO": "ВРЕДНО",
    "YA": "Я",
    "YBILI": "УБИЛИ",
    "YIDI": "УЙДИ",
    "YSHLI": "УШЛИ",
    "YSHEL": "УШЕЛ",
    "ZABRALA": "ЗАБРАЛА",
    "ZAHODYAT": "ЗАХОДЯТ",
    "ZAKRILSYA": "ЗАКРЫЛСЯ",
    "ZALA": "ЗАЛА",
    "ZANAVES": "ЗАНАВЕС",
    "ZANAVESA": "ЗАНАВЕСА",
    "ZANYATSYA": "ЗАНЯТЬСЯ",
    "ZAPOI": "ЗАПОЙ",
    "ZNAU": "ЗНАЮ",
    "ZLUSHII": "ЗЛЮЩИЙ",
    "ZOB": "ЗОБ",
    "ZVONKU": "ЗВОНКУ",
}

WORD_OVERRIDES.update(
    {
        "BOROBANNAYA": "БАРАБАННАЯ",
        "DOGD": "ДОЖДЬ",
        "DOKTOOR": "ДОКТОР",
        "DOKTOORU": "ДОКТОРУ",
        "DVEREI": "ДВЕРЕЙ",
        "IDET": "ИДЕТ",
        "KATALKA": "КАТАЛКА",
        "KATALKU": "КАТАЛКУ",
        "KATALKY": "КАТАЛКУ",
        "KIRK": "КРИК",
        "KONCE": "КОНЦЕ",
        "KONKE": "КОНЦЕ",
        "LAMPY": "ЛАМПУ",
        "LESTNIKAAMI": "ЛЕСТНИЦАМИ",
        "LESTNICAMI": "ЛЕСТНИЦАМИ",
        "LUSTTRY": "ЛЮСТРУ",
        "LYSTRY": "ЛЮСТРУ",
        "OPERAKYA": "ОПЕРАЦИЯ",
        "OPERAIYA": "ОПЕРАЦИЯ",
        "OPERI": "ОПЕРЫ",
        "PODOOSHEL": "ПОДОШЕЛ",
        "PODNIMAIT": "ПОДНИМАЕТ",
        "PODNIMAYT": "ПОДНИМАЕТ",
        "POSUDI": "ПОСУДЫ",
        "POSUDY": "ПОСУДЫ",
        "PRAVOI": "ПРАВОЙ",
        "PROFESSOR": "ПРОФЕССОР",
        "PROFESOR": "ПРОФЕССОР",
        "PROFFESOR": "ПРОФЕССОР",
        "RAAZBIL": "РАЗБИЛ",
        "SADICYA": "САДИТСЯ",
        "SERDCE": "СЕРДЦЕ",
        "SERDKE": "СЕРДЦЕ",
        "SGECH": "СЖЕЧЬ",
        "SHARIKOVAA": "ШАРИКОВА",
        "SILUETI": "СИЛУЭТЫ",
        "SILYETI": "СИЛУЭТЫ",
        "SKATERT": "СКАТЕРТЬ",
        "SOB": "СОБ",
        "TEN": "ТЕНЬ",
        "VI": "ВЫ",
        "VIHOOD": "ВЫХОД",
        "VILEZLI": "ВЫЛЕЗЛИ",
        "VISHEL": "ВЫШЕЛ",
        "VISHLI": "ВЫШЛИ",
        "VISTREL": "ВЫСТРЕЛ",
        "VIVOZYAT": "ВЫВОЗЯТ",
        "VIVOZYT": "ВЫВОЗИТ",
        "VKLUCHIL": "ВКЛЮЧИЛ",
        "VKLYCHIL": "ВКЛЮЧИЛ",
        "VOZVRASHAUCYA": "ВОЗВРАЩАЮТСЯ",
        "VOZVRASHYAUCYA": "ВОЗВРАЩАЮТСЯ",
        "VYHOD": "ВЫХОД",
        "ZAODIT": "ЗАХОДИТ",
        "ZAKRILI": "ЗАКРЫЛИ",
        "ZAKRIVAT": "ЗАКРЫВАТЬ",
        "ZTM": "ЗТМ",
    }
)

TOKEN_RE = re.compile(r"[A-Za-z]+|[А-Яа-яЁё]+|\d+|[^A-Za-zА-Яа-яЁё\d]+")

CYRILLIC_OVERRIDES = {
    "БОРОБАННАЯ": "БАРАБАННАЯ",
    "ВИ": "ВЫ",
    "ВИЛЕЗЛИ": "ВЫЛЕЗЛИ",
    "ВИСТРЕЛ": "ВЫСТРЕЛ",
    "ВИХООД": "ВЫХОД",
    "ВИШЕЛ": "ВЫШЕЛ",
    "ВИШЛИ": "ВЫШЛИ",
    "ВИВОЗЯТ": "ВЫВОЗЯТ",
    "ВИВОЗЫТ": "ВЫВОЗИТ",
    "ВКЛЬЧИЛ": "ВКЛЮЧИЛ",
    "ВОЗВРАШЯУЦЯ": "ВОЗВРАЩАЮТСЯ",
    "ДВЕРЕИ": "ДВЕРЕЙ",
    "ДОГД": "ДОЖДЬ",
    "ДОКТООР": "ДОКТОР",
    "ДОКТООРУ": "ДОКТОРУ",
    "ЗАОДИТ": "ЗАХОДИТ",
    "ЗАКРИВАТ": "ЗАКРЫВАТЬ",
    "ЗАКРИЛИ": "ЗАКРЫЛИ",
    "КИРК": "КРИК",
    "КОНКЕ": "КОНЦЕ",
    "ЛЕСТНИКААМИ": "ЛЕСТНИЦАМИ",
    "ЛУСТТРУ": "ЛЮСТРУ",
    "ОПЕРАИЯ": "ОПЕРАЦИЯ",
    "ОПЕРАКЯ": "ОПЕРАЦИЯ",
    "ОПЕРИ": "ОПЕРЫ",
    "ПОДНИМАЙТ": "ПОДНИМАЕТ",
    "ПОДООШЕЛ": "ПОДОШЕЛ",
    "ПОСУДИ": "ПОСУДЫ",
    "ПРАВОИ": "ПРАВОЙ",
    "ПРОФЕСОР": "ПРОФЕССОР",
    "ПРОФФЕСОР": "ПРОФЕССОР",
    "РААЗБИЛ": "РАЗБИЛ",
    "САДИЦЯ": "САДИТСЯ",
    "СГЕЧ": "СЖЕЧЬ",
    "СЕРДКЕ": "СЕРДЦЕ",
    "СИЛУЕТИ": "СИЛУЭТЫ",
    "СКАТЕРТ": "СКАТЕРТЬ",
    "ТЕН": "ТЕНЬ",
    "ШААРИКОВАА": "ШАРИКОВА",
}


def normalize_russian_text(value: str | None) -> str:
    if value is None:
        return ""
    text = str(value)
    normalized = "".join(_normalize_token(token) for token in TOKEN_RE.findall(text))
    normalized = normalized.replace("_", " ")
    return re.sub(r" {2,}", " ", normalized).strip()


def _normalize_token(token: str) -> str:
    if re.fullmatch(r"[А-Яа-яЁё]+", token):
        return _preserve_case(token, CYRILLIC_OVERRIDES.get(token.upper(), token.upper()))
    if not re.fullmatch(r"[A-Za-z]+", token):
        return token
    key = token.upper()
    return _preserve_case(token, WORD_OVERRIDES.get(key) or _fallback_transliterate(key))


def _preserve_case(source: str, normalized: str) -> str:
    if source.isupper():
        return normalized
    if source[:1].isupper() and source[1:].islower():
        return normalized.capitalize()
    if source.islower():
        return normalized.lower()
    return normalized


def _fallback_transliterate(word: str) -> str:
    replacements = (
        ("SHCH", "Щ"),
        ("SCH", "Щ"),
        ("CIYA", "ЦИЯ"),
        ("CIA", "ЦИЯ"),
        ("CH", "Ч"),
        ("SH", "Ш"),
        ("ZH", "Ж"),
        ("YA", "Я"),
        ("YU", "Ю"),
        ("YO", "Ё"),
        ("YE", "Е"),
        ("KH", "Х"),
        ("TS", "Ц"),
        ("IA", "Я"),
        ("IU", "Ю"),
        ("JA", "Я"),
        ("JU", "Ю"),
    )
    result = []
    index = 0
    while index < len(word):
        matched = False
        for source, target in replacements:
            if word.startswith(source, index):
                result.append(target)
                index += len(source)
                matched = True
                break
        if matched:
            continue
        char = word[index]
        result.append(_single_char(char, index, word))
        index += 1
    return "".join(result)


def _single_char(char: str, index: int, word: str) -> str:
    if char == "Y":
        if index == 0:
            return "У"
        previous = word[index - 1]
        if previous in "AEIOU":
            return "Й"
        return "Ы"
    return {
        "A": "А",
        "B": "Б",
        "C": "Ц",
        "D": "Д",
        "E": "Е",
        "F": "Ф",
        "G": "Г",
        "H": "Х",
        "I": "И",
        "J": "Ж",
        "K": "К",
        "L": "Л",
        "M": "М",
        "N": "Н",
        "O": "О",
        "P": "П",
        "Q": "К",
        "R": "Р",
        "S": "С",
        "T": "Т",
        "U": "У",
        "V": "В",
        "W": "В",
        "X": "КС",
        "Z": "З",
    }.get(char, char)
