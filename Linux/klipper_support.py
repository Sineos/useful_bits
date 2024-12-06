import os
import shutil
import subprocess
import zipfile
from datetime import datetime
import platform
import re
import time

# ANSI color codes
class Colors:
    HEADER = "\033[95m"
    OKBLUE = "\033[94m"
    OKCYAN = "\033[96m"
    OKGREEN = "\033[92m"
    WARNING = "\033[93m"
    FAIL = "\033[91m"
    ENDC = "\033[0m"
    BOLD = "\033[1m"
    UNDERLINE = "\033[4m"

def status_message(message, success=True):
    """Print status messages with color."""
    if success:
        print(f"{Colors.OKGREEN}[OK] {message}{Colors.ENDC}")
    else:
        print(f"{Colors.FAIL}[FAIL] {message}{Colors.ENDC}")

def step_message(message):
    """Print step information."""
    print(f"{Colors.OKCYAN}{message}...{Colors.ENDC}")

def ensure_empty_dir(path):
    """Ensure a directory is empty by removing and recreating it."""
    if os.path.exists(path):
        shutil.rmtree(path)
    os.makedirs(path, exist_ok=True)

def get_newest_log(log_dir, log_prefix):
    """Find the newest rotated klippy.log file."""

    # List all files in the directory
    all_files = os.listdir(log_dir)

    # Filter files that start with the prefix and have a date suffix
    log_files = [
        f for f in all_files
        if f.startswith(log_prefix) and re.match(r'^.*\.log\.\d{4}-\d{2}-\d{2}$', f)
    ]

    if not log_files:
        return None

    # Sort files by date in descending order
    try:
        log_files.sort(
            key=lambda f: datetime.strptime(f.split('.log.')[1], "%Y-%m-%d"),
            reverse=True
        )
    except Exception as e:
        print(f"Error while parsing log filenames: {e}")
        return None

    newest = log_files[0]
    return newest

def main():
    try:
        # 1. Check if klipper.service exists
        step_message("Checking klipper.service")
        klipper_service_path = "/etc/systemd/system/klipper.service"
        if not os.path.exists(klipper_service_path):
            raise FileNotFoundError(f"{klipper_service_path} does not exist.")
        status_message("klipper.service found")

        # 2. Read klipper.service content and extract EnvironmentFile
        step_message("Reading klipper.service content")
        with open(klipper_service_path, 'r') as f:
            lines = f.readlines()

        environment_file_line = [line for line in lines if line.startswith("EnvironmentFile")]
        if not environment_file_line:
            raise ValueError("EnvironmentFile not found in klipper.service.")
        environment_file_path = environment_file_line[0].split('=')[1].strip()
        status_message("EnvironmentFile path extracted")

        # 3. Check if EnvironmentFile exists
        step_message("Checking EnvironmentFile existence")
        if not os.path.exists(environment_file_path):
            raise FileNotFoundError(f"{environment_file_path} does not exist.")
        status_message("EnvironmentFile found")

        # 4. Read EnvironmentFile content and extract paths
        step_message("Reading EnvironmentFile content")
        with open(environment_file_path, 'r') as f:
            klipper_args_line = f.readline().strip()
        klipper_args = klipper_args_line.split('=')[1].strip('"').split()
        printer_cfg_path = klipper_args[1]
        log_file_path = klipper_args[5]
        status_message("Paths extracted from EnvironmentFile")

        # 5. Determine base_path for printer.cfg
        step_message("Determining base_path for printer.cfg")
        if "printer_data" in printer_cfg_path:
            base_path = printer_cfg_path.split("printer_data")[0] + "printer_data/"
        else:
            base_path = printer_cfg_path
            print(f"{Colors.WARNING}Warning: Non-standard installation for printer.cfg at {base_path}{Colors.ENDC}")
        status_message(f"Printer config path: {base_path}")

        # 6. Determine base_path for log file
        step_message("Determining base_path for log file")
        if "printer_data" in log_file_path:
            base_path_log = log_file_path.split("printer_data")[0] + "printer_data/"
        else:
            base_path_log = log_file_path
            print(f"{Colors.WARNING}Warning: Non-standard installation for log file at {base_path_log}{Colors.ENDC}")
        status_message(f"Log file path: {base_path_log}")

        # 7. Prepare support directory
        step_message("Preparing support directory")
        support_dir = "/tmp/klipper_support"
        ensure_empty_dir(support_dir)
        status_message("Support directory prepared")

        # Copy selective logs
        step_message("Copying selective logs")
        if "printer_data" in log_file_path:
            log_dir = os.path.dirname(log_file_path)

            files_to_copy = ["klippy.log", "moonraker.log"]
            for file in files_to_copy:
                file_path = os.path.join(log_dir, file)
                if os.path.exists(file_path):
                    shutil.copy(file_path, os.path.join(support_dir, file))
                    status_message(f"Copied {file}")

            newest_log = get_newest_log(log_dir, "klippy.log")
            if newest_log:
                shutil.copy(os.path.join(log_dir, newest_log), os.path.join(support_dir, newest_log))
                status_message(f"Copied last rolled-over log: {newest_log}")
            else:
                status_message(f"No archived klippy log found.")

        else:
            shutil.copy(log_file_path, os.path.join(support_dir, "klippy.log"))
        status_message("Selective logs copied")

        # Copy printer.cfg
        step_message("Copying printer.cfg")
        if "printer_data" in printer_cfg_path:
            shutil.copytree(os.path.dirname(printer_cfg_path), os.path.join(support_dir, "config"))
        else:
            shutil.copy(printer_cfg_path, os.path.join(support_dir, "printer.cfg"))
        status_message("Printer.cfg copied")

        # Collect OS information
        step_message("Collecting OS information")
        os_info_path = os.path.join(support_dir, "OS_Information.txt")
        with open(os_info_path, 'w') as f:
            subprocess.run(["uname", "-a"], stdout=f, text=True)
            f.write("\n")
            subprocess.run(["cat", "/etc/os-release"], stdout=f, text=True)
            f.write("\n")
            f.write(f"Platform: {platform.platform()}\n")
        status_message("OS information collected")

        # Collect network information
        step_message("Collecting network information")
        network_info_path = os.path.join(support_dir, "Network_Information.txt")
        with open(network_info_path, 'w') as f:
            subprocess.run(["ip", "-details", "-s", "link", "show"], stdout=f, text=True)
        status_message("Network information collected")

        # Collect dmesg information
        step_message("Collecting dmesg information")
        dmesg_path = os.path.join(support_dir, "dmesg.txt")
        with open(dmesg_path, 'w') as f:
            subprocess.run(["sudo", "dmesg"], stdout=f, text=True)
        status_message("dmesg information collected")

        # Compress the folder
        step_message("Compressing support folder")
        zip_path = "/tmp/klipper_support.zip"
        with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
            for root, dirs, files in os.walk(support_dir):
                for file in files:
                    abs_path = os.path.join(root, file)
                    arcname = os.path.relpath(abs_path, support_dir)
                    timestamp = time.strftime("%Y%m%d_%H%M%S")
                    arcname_with_timestamp = f"{arcname}_{timestamp}"
                    zipf.write(abs_path, arcname_with_timestamp)
        status_message("Support folder compressed")

        # Final message
        timestamp = time.strftime("%Y%m%d_%H%M%S")
        if "printer_data" in base_path:
            final_path = os.path.join(base_path, "logs", f"klipper_support_{timestamp}.zip")
            shutil.copy(zip_path, final_path)
            print(f"{Colors.BOLD}{Colors.OKGREEN}Support ZIP created: {final_path}{Colors.ENDC}")
            print(f"{Colors.BOLD}{Colors.WARNING}Get the file in the logs section of the webinterface. Refresh might be needed!{Colors.ENDC}")
        else:
            final_path = f"/tmp/klipper_support_{timestamp}.zip"
            shutil.copy(zip_path, final_path)
            print(f"{Colors.BOLD}{Colors.OKGREEN}Support ZIP created: {final_path}{Colors.ENDC}")

    except Exception as e:
        status_message(str(e), success=False)

if __name__ == "__main__":
    main()
