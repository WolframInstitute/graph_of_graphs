#!/usr/bin/env python3
"""Check the archived Morita certificate without computing matrix ranks."""
import argparse
import json
from pathlib import Path
from check_forested_complex import Complex, triangle_product, verify_witness

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('archive',nargs='?',type=Path,
                    default=Path(__file__).with_name('forested-complex.json'))
args = parser.parse_args()
archive = json.loads(args.archive.read_text())
record = next(r for r in archive['results'] if r['rank'] == 4)
witness = record['degree_four_witness']
complex = Complex(4,archive['backend'])
verify_witness(complex,witness)
assert triangle_product(complex,witness) == witness['triangle_product']
print(f"Rank-four certificate: Cz=Rz=0, phi D5=0, phi(z)={witness['pairing']}; "
      f"{len(witness['cycle'])} cycle terms, {len(witness['cocycle'])} cocycle terms.")
