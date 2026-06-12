import json
import httpx
import paramiko
import os
import shutil
from pathlib import Path
from . import models
from urllib.parse import quote

ROOT_FOLDER = "MA2_passports"

async def sync_to_cloud(user: models.User, file_path: Path, project_title: str):
    """Uploads a single file to the active storage (Yandex or SFTP)."""
    if not file_path.exists(): return
    mode = user.storage_mode
    if mode == "temp": return
    
    filename = file_path.name
    if "photos" in str(file_path.parent):
        rel_path = f"{ROOT_FOLDER}/{project_title}/photos/{filename}"
    else:
        rel_path = f"{ROOT_FOLDER}/{project_title}/{filename}"

    if mode == "yandex_disk":
        token = user.yandex_manual_token or (json.loads(user.yandex_disk_token).get("access_token") if user.yandex_disk_token else None)
        if not token: return
        headers = {"Authorization": f"OAuth {token}"}
        async with httpx.AsyncClient(timeout=60.0, follow_redirects=True) as client:
            parts = rel_path.split('/')[:-1]
            curr = "app:/"
            for p in parts:
                curr = f"{curr}{p}/"
                await client.put("https://cloud-api.yandex.net/v1/disk/resources", params={"path": curr.rstrip('/')}, headers=headers)
            up_url_api = "https://cloud-api.yandex.net/v1/disk/resources/upload"
            resp = await client.get(up_url_api, params={"path": f"app:/{rel_path}", "overwrite": "true"}, headers=headers)
            if resp.status_code == 200:
                href = resp.json()["href"]
                with open(file_path, "rb") as f:
                    content = f.read()
                    if len(content) > 0:
                        async with httpx.AsyncClient(timeout=60.0, follow_redirects=True) as dl_client:
                            await dl_client.put(href, content=content)
    elif mode == "sftp" and user.sftp_config:
        try:
            config = json.loads(user.sftp_config)
            ssh = paramiko.SSHClient(); ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            ssh.connect(config["host"], port=int(config.get("port", 22)), username=config["username"], password=config.get("password"), timeout=10)
            sftp = ssh.open_sftp()
            parts = rel_path.split('/')[:-1]
            curr = ""
            for p in parts:
                curr = f"{curr}/{p}" if curr else p
                try: sftp.stat(curr)
                except FileNotFoundError: sftp.mkdir(curr)
            sftp.put(str(file_path), rel_path)
            sftp.close(); ssh.close()
        except: pass

async def list_cloud_projects(user: models.User) -> list[str]:
    mode = user.storage_mode
    if mode == "sftp" and user.sftp_config:
        try:
            config = json.loads(user.sftp_config)
            ssh = paramiko.SSHClient(); ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            ssh.connect(config["host"], port=int(config.get("port", 22)), username=config["username"], password=config.get("password"), timeout=10)
            sftp = ssh.open_sftp()
            try:
                items = sftp.listdir(ROOT_FOLDER)
                res = [i for i in items if sftp.lstat(f"{ROOT_FOLDER}/{i}").st_mode & 0o40000]
                sftp.close(); ssh.close(); return res
            except: return []
        except: return []
    elif mode == "yandex_disk":
        token = user.yandex_manual_token or (json.loads(user.yandex_disk_token).get("access_token") if user.yandex_disk_token else None)
        if not token: return []
        headers = {"Authorization": f"OAuth {token}"}
        async with httpx.AsyncClient(timeout=30.0, follow_redirects=True) as client:
            resp = await client.get("https://cloud-api.yandex.net/v1/disk/resources", params={"path": f"app:/{ROOT_FOLDER}"}, headers=headers)
            if resp.status_code == 200:
                return [i["name"] for i in resp.json().get("_embedded", {}).get("items", []) if i["type"] == "dir"]
    return []

async def get_cloud_files(user: models.User, project_title: str) -> list[str]:
    mode = user.storage_mode
    if mode == "sftp" and user.sftp_config:
        try:
            config = json.loads(user.sftp_config)
            ssh = paramiko.SSHClient(); ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            ssh.connect(config["host"], port=int(config.get("port", 22)), username=config["username"], password=config.get("password"), timeout=10)
            sftp = ssh.open_sftp()
            try:
                target = f"{ROOT_FOLDER}/{project_title}"
                items = sftp.listdir(target)
                sftp.close(); ssh.close()
                return [i for i in items if i.endswith(('.pdf', '.xlsx')) or i.endswith('_new.xml')]
            except: return []
        except: return []
    elif mode == "yandex_disk":
        token = user.yandex_manual_token or (json.loads(user.yandex_disk_token).get("access_token") if user.yandex_disk_token else None)
        if not token: return []
        headers = {"Authorization": f"OAuth {token}"}
        async with httpx.AsyncClient(timeout=30.0, follow_redirects=True) as client:
            resp = await client.get("https://cloud-api.yandex.net/v1/disk/resources", params={"path": f"app:/{ROOT_FOLDER}/{project_title}", "limit": 100}, headers=headers)
            if resp.status_code == 200:
                files = [i["name"] for i in resp.json().get("_embedded", {}).get("items", []) if i["type"] == "file"]
                return [f for f in files if f.endswith(('.pdf', '.xlsx')) or f.endswith('_new.xml')]
    return []

async def download_from_cloud(user: models.User, project_title: str, local_dir: Path):
    """Full download of project from cloud."""
    mode = user.storage_mode
    local_dir.mkdir(parents=True, exist_ok=True)
    photo_dir = local_dir / "photos"; photo_dir.mkdir(exist_ok=True)
    
    if mode == "sftp" and user.sftp_config:
        try:
            config = json.loads(user.sftp_config)
            ssh = paramiko.SSHClient(); ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            ssh.connect(config["host"], port=int(config.get("port", 22)), username=config["username"], password=config.get("password"), timeout=15)
            sftp = ssh.open_sftp()
            rem_dir = f"{ROOT_FOLDER}/{project_title}"
            for f in sftp.listdir(rem_dir):
                if f in {"project.json", "passport_state.json"} or f.endswith(".xml") or f.endswith((".pdf", ".xlsx")):
                    sftp.get(f"{rem_dir}/{f}", str(local_dir / f))
            try:
                for f in sftp.listdir(f"{rem_dir}/photos"):
                    sftp.get(f"{rem_dir}/photos/{f}", str(photo_dir / f))
            except: pass
            sftp.close(); ssh.close()
        except Exception as e: pass

    elif mode == "yandex_disk":
        token = user.yandex_manual_token or (json.loads(user.yandex_disk_token).get("access_token") if user.yandex_disk_token else None)
        if not token: return
        headers = {"Authorization": f"OAuth {token}"}
        async with httpx.AsyncClient(timeout=120.0, follow_redirects=True) as client:
            remote_path = f"app:/{ROOT_FOLDER}/{project_title}"
            resp = await client.get("https://cloud-api.yandex.net/v1/disk/resources", params={"path": remote_path, "limit": 100}, headers=headers)
            if resp.status_code == 200:
                for item in resp.json().get("_embedded", {}).get("items", []):
                    if item["type"] == "file" and (item["name"] in {"project.json", "passport_state.json"} or item["name"].endswith(".xml") or item["name"].endswith((".pdf", ".xlsx"))):
                        dl_res = await client.get("https://cloud-api.yandex.net/v1/disk/resources/download", params={"path": item["path"]}, headers=headers)
                        if dl_res.status_code == 200:
                            async with httpx.AsyncClient(timeout=60.0, follow_redirects=True) as dl_client:
                                f_data = await dl_client.get(dl_res.json()["href"])
                                with open(local_dir / item["name"], "wb") as f: f.write(f_data.content)
            p_resp = await client.get("https://cloud-api.yandex.net/v1/disk/resources", params={"path": f"{remote_path}/photos", "limit": 1000}, headers=headers)
            if p_resp.status_code == 200:
                for item in p_resp.json().get("_embedded", {}).get("items", []):
                    dl_res = await client.get("https://cloud-api.yandex.net/v1/disk/resources/download", params={"path": item["path"]}, headers=headers)
                    if dl_res.status_code == 200:
                        async with httpx.AsyncClient(timeout=60.0, follow_redirects=True) as dl_client:
                            f_data = await dl_client.get(dl_res.json()["href"])
                            with open(photo_dir / item["name"], "wb") as f: f.write(f_data.content)

    # FIX LOCAL STATE
    json_path = local_dir / "project.json"
    if json_path.exists():
        with open(json_path, "r", encoding="utf-8") as f: data = json.load(f)
        base_title = project_title[:-9] if project_title.endswith("_passport") else project_title
        data["title"] = base_title
        new_xml = f"{base_title}.xml"
        for f in local_dir.iterdir():
            if f.suffix == ".xml":
                if f.name != new_xml:
                    f.rename(local_dir / new_xml)
                data["xml_file"] = new_xml
                break
        for row in data.get("rows", []):
            if row.get("photo_path"):
                row["photo_path"] = str(local_dir / "photos" / Path(row["photo_path"]).name)
        with open(json_path, "w", encoding="utf-8") as f: json.dump(data, f, indent=2)

async def delete_cloud_project(user: models.User, project_title: str):
    if user.storage_mode == "yandex_disk":
        token = user.yandex_manual_token or (json.loads(user.yandex_disk_token).get("access_token") if user.yandex_disk_token else None)
        headers = {"Authorization": f"OAuth {token}"}
        async with httpx.AsyncClient(timeout=30.0, follow_redirects=True) as client:
            await client.delete("https://cloud-api.yandex.net/v1/disk/resources", params={"path": f"app:/{ROOT_FOLDER}/{project_title}"}, headers=headers)
    elif user.storage_mode == "sftp" and user.sftp_config:
        try:
            config = json.loads(user.sftp_config)
            ssh = paramiko.SSHClient(); ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            ssh.connect(config["host"], port=int(config.get("port", 22)), username=config["username"], password=config.get("password"))
            sftp = ssh.open_sftp(); target = f"{ROOT_FOLDER}/{project_title}"
            try:
                for f in sftp.listdir(f"{target}/photos"): sftp.remove(f"{target}/photos/{f}")
                sftp.rmdir(f"{target}/photos")
            except: pass
            for f in sftp.listdir(target): sftp.remove(f"{target}/{f}")
            sftp.rmdir(target); sftp.close(); ssh.close()
        except: pass

async def rename_cloud_project(user: models.User, old_name: str, new_name: str):
    old_base = old_name[:-9] if old_name.endswith("_passport") else old_name
    new_base = new_name[:-9] if new_name.endswith("_passport") else new_name
    if user.storage_mode == "yandex_disk":
        token = user.yandex_manual_token or (json.loads(user.yandex_disk_token).get("access_token") if user.yandex_disk_token else None)
        headers = {"Authorization": f"OAuth {token}"}
        async with httpx.AsyncClient(timeout=60.0, follow_redirects=True) as client:
            old_p = f"app:/{ROOT_FOLDER}/{old_name}"; new_p = f"app:/{ROOT_FOLDER}/{new_name}"
            resp = await client.get("https://cloud-api.yandex.net/v1/disk/resources", params={"path": old_p, "limit": 100}, headers=headers)
            if resp.status_code == 200:
                for i in resp.json().get("_embedded", {}).get("items", []):
                    if i["type"] == "file" and i["name"].startswith(old_base):
                        new_fname = i["name"].replace(old_base, new_base, 1)
                        await client.post("https://cloud-api.yandex.net/v1/disk/resources/move", params={"from": i["path"], "path": f"{old_p}/{new_fname}"}, headers=headers)
            await client.post("https://cloud-api.yandex.net/v1/disk/resources/move", params={"from": old_p, "path": new_p}, headers=headers)
    elif user.storage_mode == "sftp" and user.sftp_config:
        try:
            config = json.loads(user.sftp_config)
            ssh = paramiko.SSHClient(); ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            ssh.connect(config["host"], port=int(config.get("port", 22)), username=config["username"], password=config.get("password"))
            sftp = ssh.open_sftp()
            target = f"{ROOT_FOLDER}/{old_name}"
            for f in sftp.listdir(target):
                if f.startswith(old_base): sftp.rename(f"{target}/{f}", f"{target}/{f.replace(old_base, new_base, 1)}")
            sftp.rename(f"{ROOT_FOLDER}/{old_name}", f"{ROOT_FOLDER}/{new_name}")
            sftp.close(); ssh.close()
        except: pass
