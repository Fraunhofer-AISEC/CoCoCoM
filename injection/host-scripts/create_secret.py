#!/usr/bin/python3
# Copyright 2020-2021 Joana Pecholt, Fraunhofer AISEC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


# Also see James Bottomley's blog here:
# https://blog.hansenpartnership.com/deploying-encrypted-images-for-confidential-computing/
# and his sevsecret tool
# https://blog.hansenpartnership.com/wp-uploads/2020/12/sevsecret.txt

# Description: This script packages a provided secret (password) as
# required by the OVMF.

import sys
from os import path

if len(sys.argv) != 3:
	sys.exit("Expecting the password for the disk encryption key and an out folder as parameters.")

pw=sys.argv[1]
out=sys.argv[2]
if not path.exists(path.split(path.abspath(out))[0]):
	print("Specified out directory does not exist")
	exit()

# header + pw length + null byte
l = 40 + len(pw) + 1

secret = bytearray(l);
# GRUB_EFI_SEVSECRET_TABLE_HEADER_GUID = {1e74f542-71dd-4d66-963e-ef4287ff173b}
secret[0:16] = bytearray.fromhex('42f5741edd71664d963eef4287ff173b')
secret[16:20] = len(secret).to_bytes(4, byteorder='little')
# GRUB_EFI_DISKPASSWD_GUID = {736869e5-84f0-4973-92ec-06879ce3da0b}
secret[20:36] = bytearray.fromhex('e5696873f084734992ec06879ce3da0b')
secret[36:40] = (20 + len(pw) + 1).to_bytes(4, byteorder='little')
secret[40:40+len(pw)] = pw.encode()
f = open(out, "wb")
f.write(secret)
f.close()
