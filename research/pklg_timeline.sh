#!/bin/sh
# Zeitleiste aus einem PacketLogger-Trace (iOS als BLE-Peripheral gegenüber der Pumpe).
# Zeigt Advertising der App (Handle 0), Verbindungs-Events, SMP, MTU-Exchange.
# Nutzung: research/pklg_timeline.sh <trace.pklg> [stunden_offset]
F="$1"; OFF="${2:--2}"
tshark -r "$F" -Y "(bthci_cmd.opcode==0x207f && bthci_cmd.advertising_handle==0) || (bthci_cmd.opcode==0x2037 && bthci_cmd.advertising_handle==0) || (bthci_cmd.opcode==0x2039) || bthci_evt.le_meta_subevent || btsmp || btatt.opcode==0x02 || btatt.opcode==0x03 || bthci_evt.code==0x05 || bthci_evt.code==0x08" \
  -T fields -E separator='|' -e frame.number -e frame.time -e _ws.col.Info \
  -e bthci_cmd.le_advts_interval_min -e btcommon.eir_ad.entry.uuid_16 -e btcommon.eir_ad.entry.device_name \
  -e btatt.client_rx_mtu -e btatt.server_rx_mtu -e bthci_evt.reason -e bthci_cmd.advertising_handle 2>/dev/null |
awk -F'|' -v off="$OFF" '{ split($2,t,"T"); split(t[2],h,":"); s=substr(h[3],1,6); hh=(h[1]+off+24)%24;
  x=""; if($4!="")x=x" int="$4; if($5!="")x=x" uuid="$5; if($6!="")x=x" name=\""$6"\""; if($7!="")x=x" mtu_c="$7; if($8!="")x=x" mtu_s="$8; if($9!="")x=x" reason="$9; if($10!="")x=x" h="$10;
  printf "%6s %02d:%s:%s  %s%s\n",$1,hh,h[2],s,$3,x }'
