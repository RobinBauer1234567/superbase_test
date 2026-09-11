"""Isolated PostgreSQL 17 integration test. No network or production credentials.
The fixture uses inspected production table shapes; Auth and Cron are stubbed.
Usage: python supabase/tests/run_season_tests.py [--port 55441]
"""
import argparse, os, subprocess, uuid
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--port',default='55441');args=p.parse_args()
root=Path(__file__).resolve().parents[2]
psql=os.environ.get('PSQL',r'C:\Program Files\PostgreSQL\17\bin\psql.exe')
db='managerspiel_test_seasons_'+uuid.uuid4().hex[:8]
base=[psql,'-X','-h','127.0.0.1','-p',args.port,'-U','postgres','-v','ON_ERROR_STOP=1']
def sql(value,database=db):
    r=subprocess.run(base+['-d',database],input=value,encoding='utf-8',capture_output=True)
    if r.returncode: raise RuntimeError(r.stderr+'\n'+r.stdout)
    return r.stdout
sql('CREATE DATABASE '+db,'postgres')
fixture=(root/'supabase/tests/production_shape.sql').read_text(encoding='utf-8-sig')
for role in ['anon','authenticated','service_role']:
    line='CREATE ROLE '+role+(' BYPASSRLS' if role=='service_role' else '')+';'
    fixture=fixture.replace(line,"DO $$ BEGIN "+line+" EXCEPTION WHEN duplicate_object THEN NULL; END $$;")
sql(fixture)
sql((root/'supabase/tests/legacy_fixture.sql').read_text(encoding='utf-8-sig'))
for path in sorted((root/'supabase/migrations').glob('*season_lifecycle.sql')):
    sql('BEGIN;\n'+path.read_text(encoding='utf-8-sig')+'\nCOMMIT;')
    print('PASS migration:',path.name)
sql((root/'supabase/tests/season_lifecycle.sql').read_text(encoding='utf-8-sig'))
print('PASS lifecycle, permissions, preservation, chain, idempotency and cron registration')
print('Isolated database retained:',db)

# Separate connections test actual locking, rather than sequential retries.
from concurrent.futures import ThreadPoolExecutor
sql("INSERT INTO season(id,name,tournament_id,is_active) VALUES(102,'26/27',17,false);")
with ThreadPoolExecutor(max_workers=4) as pool:
    list(pool.map(lambda _:sql("SELECT activate_season(102);"),range(4)))
result=sql("SELECT count(*) FROM sync_tasks WHERE season_id=102 AND task_type='FETCH_TEAMS';")
assert '\n     1\n' in result, result
sql("INSERT INTO season_teams VALUES(102,11),(102,12); INSERT INTO season_players(season_id,player_id,team_id) VALUES(102,501,11),(102,502,12); UPDATE sync_tasks SET status='COMPLETED' WHERE season_id=102 AND task_type='FETCH_TEAMS';")
with ThreadPoolExecutor(max_workers=2) as pool:
    list(pool.map(lambda team:sql("UPDATE sync_tasks SET status='COMPLETED' WHERE season_id=102 AND task_type='FETCH_TEAM_SQUAD' AND team_id="+str(team)),[11,12]))
result=sql("SELECT status FROM sync_tasks WHERE season_id=102 AND task_type='FETCH_ROUNDS';")
assert 'PENDING' in result, result
print('PASS concurrent activation and concurrent squad fan-in')
