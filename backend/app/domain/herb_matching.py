"""Best-effort matching of a user's free-text herb name to the herbs catalog.

Not a diagnosis or approval of anything about the herb — purely so the UI
can show "did you mean X?" and so requests link to a canonical herb_id
when possible. herb_name_raw always keeps what the user actually typed.
"""

from __future__ import annotations

import difflib
import re
from typing import TypedDict


class HerbRow(TypedDict):
    id: str
    slug: str
    name_he: str
    name_en: str | None


def _normalize(text: str) -> str:
    text = text.strip().lower()
    # Collapse Hebrew niqqud/whitespace variance and stray punctuation so
    # "ג'ינג'ר" and "ג׳ינג׳ר" compare equal.
    text = re.sub(r"[֑-ׇ'‘’׳״\"\-]", "", text)
    text = re.sub(r"\s+", " ", text)
    return text


def find_best_match(raw_name: str, herbs: list[HerbRow], cutoff: float = 0.72) -> HerbRow | None:
    """Returns the best matching herb row, or None if nothing clears the cutoff.

    Tries an exact (normalized) match on name_he/name_en/slug first, then
    falls back to fuzzy matching so small typos still resolve.
    """
    if not raw_name or not herbs:
        return None

    normalized_input = _normalize(raw_name)

    candidates: dict[str, HerbRow] = {}
    for herb in herbs:
        for key in (herb["name_he"], herb.get("name_en"), herb["slug"]):
            if key:
                candidates[_normalize(key)] = herb

    if normalized_input in candidates:
        return candidates[normalized_input]

    close = difflib.get_close_matches(normalized_input, candidates.keys(), n=1, cutoff=cutoff)
    return candidates[close[0]] if close else None
