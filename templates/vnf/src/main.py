import os
import time


def main():
    vnf_id = os.getenv("VNF_ID", "unknown")
    gnb_id = os.getenv("GNB_ID", "unknown")
    fabric_peer = os.getenv("FABRIC_PEER", "unknown")

    print("==============================================")
    print(" VNF starting")
    print("==============================================")
    print(f"VNF ID       : {vnf_id}")
    print(f"gNB ID       : {gnb_id}")
    print(f"Fabric Peer  : {fabric_peer}")
    print("==============================================")

    while True:
        time.sleep(60)


if __name__ == "__main__":
    main()