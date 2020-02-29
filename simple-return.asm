;extcodecopy(0x027F633732930a97FEF86051db2b5790d63373F6, 0, 1, 20)
;log1(0, 32, codesize());
;return(0, 32)

codecopy(0, $contract, #contract)
return(0, #contract)

@contract{
   mstore(0, 0x42434546)
   return(0, 31)
}
