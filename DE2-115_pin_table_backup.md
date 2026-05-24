# DE2-115 Pin Table Backup

- Source: `E:\Main\JuniorII\NonExam\FPGA\DE2-115引脚表.xlsx`
- Sheet: `Sheet1`
- Clean rows exported: `525`
- Groups: `23`
- Columns: `Group | Signal | Direction | Location | I/O Bank | VREF Group`

## Group Index

| Group | Rows |
| --- | ---: |
| AUD | 6 |
| CLOCK | 3 |
| DRAM | 57 |
| EEP | 2 |
| ENET | 45 |
| EX | 7 |
| FL | 37 |
| GPIO | 36 |
| HEX | 56 |
| HSMC | 82 |
| I2C | 3 |
| KEY | 4 |
| LCD | 13 |
| LED | 27 |
| OTG | 30 |
| PS2 | 4 |
| SD | 7 |
| SMA | 2 |
| SRAM | 41 |
| SW | 18 |
| TD | 12 |
| UART | 4 |
| VGA | 29 |

## AUD

| Signal | Direction | Location | I/O Bank | VREF Group |
| --- | --- | --- | ---: | --- |
| AUD_ADCDAT | Input | PIN_D2 | 1 | B1_N0 |
| AUD_ADCLRCK | Bidir | PIN_C2 | 1 | B1_N0 |
| AUD_BCLK | Bidir | PIN_F2 | 1 | B1_N1 |
| AUD_DACDAT | Output | PIN_D1 | 1 | B1_N0 |
| AUD_DACLRCK | Bidir | PIN_E3 | 1 | B1_N0 |
| AUD_XCK | Output | PIN_E1 | 1 | B1_N0 |

## CLOCK

| Signal | Direction | Location | I/O Bank | VREF Group |
| --- | --- | --- | ---: | --- |
| CLOCK2_50 | Input | PIN_AG14 | 3 | B3_N0 |
| CLOCK3_50 | Input | PIN_AG15 | 4 | B4_N2 |
| CLOCK_50 | Input | PIN_Y2 | 2 | B2_N0 |

## DRAM

| Signal | Direction | Location | I/O Bank | VREF Group |
| --- | --- | --- | ---: | --- |
| DRAM_ADDR[12] | Output | PIN_Y7 | 2 | B2_N2 |
| DRAM_ADDR[11] | Output | PIN_AA5 | 2 | B2_N2 |
| DRAM_ADDR[10] | Output | PIN_R5 | 2 | B2_N0 |
| DRAM_ADDR[9] | Output | PIN_Y6 | 2 | B2_N2 |
| DRAM_ADDR[8] | Output | PIN_Y5 | 2 | B2_N2 |
| DRAM_ADDR[7] | Output | PIN_AA7 | 2 | B2_N2 |
| DRAM_ADDR[6] | Output | PIN_W7 | 2 | B2_N2 |
| DRAM_ADDR[5] | Output | PIN_W8 | 2 | B2_N2 |
| DRAM_ADDR[4] | Output | PIN_V5 | 2 | B2_N1 |
| DRAM_ADDR[3] | Output | PIN_P1 | 1 | B1_N2 |
| DRAM_ADDR[2] | Output | PIN_U8 | 2 | B2_N1 |
| DRAM_ADDR[1] | Output | PIN_V8 | 2 | B2_N1 |
| DRAM_ADDR[0] | Output | PIN_R6 | 2 | B2_N0 |
| DRAM_BA[1] | Output | PIN_R4 | 2 | B2_N0 |
| DRAM_BA[0] | Output | PIN_U7 | 2 | B2_N1 |
| DRAM_CAS_N | Output | PIN_V7 | 2 | B2_N1 |
| DRAM_CKE | Output | PIN_AA6 | 2 | B2_N2 |
| DRAM_CLK | Output | PIN_AE5 | 3 | B3_N2 |
| DRAM_CS_N | Output | PIN_T4 | 2 | B2_N0 |
| DRAM_DQ[31] | Bidir | PIN_U1 | 2 | B2_N0 |
| DRAM_DQ[30] | Bidir | PIN_U4 | 2 | B2_N0 |
| DRAM_DQ[29] | Bidir | PIN_T3 | 2 | B2_N0 |
| DRAM_DQ[28] | Bidir | PIN_R3 | 2 | B2_N0 |
| DRAM_DQ[27] | Bidir | PIN_R2 | 2 | B2_N0 |
| DRAM_DQ[26] | Bidir | PIN_R1 | 2 | B2_N0 |
| DRAM_DQ[25] | Bidir | PIN_R7 | 2 | B2_N0 |
| DRAM_DQ[24] | Bidir | PIN_U5 | 2 | B2_N1 |
| DRAM_DQ[23] | Bidir | PIN_L7 | 1 | B1_N2 |
| DRAM_DQ[22] | Bidir | PIN_M7 | 1 | B1_N2 |
| DRAM_DQ[21] | Bidir | PIN_M4 | 1 | B1_N1 |
| DRAM_DQ[20] | Bidir | PIN_N4 | 1 | B1_N2 |
| DRAM_DQ[19] | Bidir | PIN_N3 | 1 | B1_N2 |
| DRAM_DQ[18] | Bidir | PIN_P2 | 1 | B1_N2 |
| DRAM_DQ[17] | Bidir | PIN_L8 | 1 | B1_N2 |
| DRAM_DQ[16] | Bidir | PIN_M8 | 1 | B1_N2 |
| DRAM_DQ[15] | Bidir | PIN_AC2 | 2 | B2_N1 |
| DRAM_DQ[14] | Bidir | PIN_AB3 | 2 | B2_N1 |
| DRAM_DQ[13] | Bidir | PIN_AC1 | 2 | B2_N1 |
| DRAM_DQ[12] | Bidir | PIN_AB2 | 2 | B2_N0 |
| DRAM_DQ[11] | Bidir | PIN_AA3 | 2 | B2_N1 |
| DRAM_DQ[10] | Bidir | PIN_AB1 | 2 | B2_N0 |
| DRAM_DQ[9] | Bidir | PIN_Y4 | 2 | B2_N1 |
| DRAM_DQ[8] | Bidir | PIN_Y3 | 2 | B2_N1 |
| DRAM_DQ[7] | Bidir | PIN_U3 | 2 | B2_N0 |
| DRAM_DQ[6] | Bidir | PIN_V1 | 2 | B2_N0 |
| DRAM_DQ[5] | Bidir | PIN_V2 | 2 | B2_N0 |
| DRAM_DQ[4] | Bidir | PIN_V3 | 2 | B2_N0 |
| DRAM_DQ[3] | Bidir | PIN_W1 | 2 | B2_N1 |
| DRAM_DQ[2] | Bidir | PIN_V4 | 2 | B2_N0 |
| DRAM_DQ[1] | Bidir | PIN_W2 | 2 | B2_N0 |
| DRAM_DQ[0] | Bidir | PIN_W3 | 2 | B2_N2 |
| DRAM_DQM[3] | Output | PIN_N8 | 1 | B1_N2 |
| DRAM_DQM[2] | Output | PIN_K8 | 1 | B1_N2 |
| DRAM_DQM[1] | Output | PIN_W4 | 2 | B2_N2 |
| DRAM_DQM[0] | Output | PIN_U2 | 2 | B2_N0 |
| DRAM_RAS_N | Output | PIN_U6 | 2 | B2_N1 |
| DRAM_WE_N | Output | PIN_V6 | 2 | B2_N1 |

## EEP

| Signal | Direction | Location | I/O Bank | VREF Group |
| --- | --- | --- | ---: | --- |
| EEP_I2C_SCLK | Output | PIN_D14 | 8 | B8_N0 |
| EEP_I2C_SDAT | Bidir | PIN_E14 | 8 | B8_N0 |

## ENET

| Signal | Direction | Location | I/O Bank | VREF Group |
| --- | --- | --- | ---: | --- |
| ENET0_GTX_CLK | Output | PIN_A17 | 7 | B7_N2 |
| ENET0_INT_N | Input | PIN_A21 | 7 | B7_N1 |
| ENET0_LINK100 | Input | PIN_C14 | 8 | B8_N0 |
| ENET0_MDC | Output | PIN_C20 | 7 | B7_N1 |
| ENET0_MDIO | Bidir | PIN_B21 | 7 | B7_N1 |
| ENET0_RST_N | Output | PIN_C19 | 7 | B7_N1 |
| ENET0_RX_CLK | Input | PIN_A15 | 7 | B7_N2 |
| ENET0_RX_COL | Input | PIN_E15 | 7 | B7_N2 |
| ENET0_RX_CRS | Input | PIN_D15 | 7 | B7_N2 |
| ENET0_RX_DATA[3] | Input | PIN_C15 | 7 | B7_N2 |
| ENET0_RX_DATA[2] | Input | PIN_D17 | 7 | B7_N1 |
| ENET0_RX_DATA[1] | Input | PIN_D16 | 7 | B7_N2 |
| ENET0_RX_DATA[0] | Input | PIN_C16 | 7 | B7_N2 |
| ENET0_RX_DV | Input | PIN_C17 | 7 | B7_N1 |
| ENET0_RX_ER | Input | PIN_D18 | 7 | B7_N1 |
| ENET0_TX_CLK | Input | PIN_B17 | 7 | B7_N2 |
| ENET0_TX_DATA[3] | Output | PIN_B19 | 7 | B7_N1 |
| ENET0_TX_DATA[2] | Output | PIN_A19 | 7 | B7_N1 |
| ENET0_TX_DATA[1] | Output | PIN_D19 | 7 | B7_N1 |
| ENET0_TX_DATA[0] | Output | PIN_C18 | 7 | B7_N1 |
| ENET0_TX_EN | Output | PIN_A18 | 7 | B7_N1 |
| ENET0_TX_ER | Output | PIN_B18 | 7 | B7_N1 |
| ENET1_GTX_CLK | Output | PIN_C23 | 7 | B7_N0 |
| ENET1_INT_N | Input | PIN_D24 | 7 | B7_N0 |
| ENET1_LINK100 | Input | PIN_D13 | 8 | B8_N0 |
| ENET1_MDC | Output | PIN_D23 | 7 | B7_N0 |
| ENET1_MDIO | Bidir | PIN_D25 | 7 | B7_N0 |
| ENET1_RST_N | Output | PIN_D22 | 7 | B7_N0 |
| ENET1_RX_CLK | Input | PIN_B15 | 7 | B7_N2 |
| ENET1_RX_COL | Input | PIN_B22 | 7 | B7_N1 |
| ENET1_RX_CRS | Input | PIN_D20 | 7 | B7_N1 |
| ENET1_RX_DATA[3] | Input | PIN_D21 | 7 | B7_N0 |
| ENET1_RX_DATA[2] | Input | PIN_A23 | 7 | B7_N0 |
| ENET1_RX_DATA[1] | Input | PIN_C21 | 7 | B7_N0 |
| ENET1_RX_DATA[0] | Input | PIN_B23 | 7 | B7_N0 |
| ENET1_RX_DV | Input | PIN_A22 | 7 | B7_N1 |
| ENET1_RX_ER | Input | PIN_C24 | 7 | B7_N0 |
| ENET1_TX_CLK | Input | PIN_C22 | 7 | B7_N0 |
| ENET1_TX_DATA[3] | Output | PIN_C26 | 7 | B7_N0 |
| ENET1_TX_DATA[2] | Output | PIN_B26 | 7 | B7_N0 |
| ENET1_TX_DATA[1] | Output | PIN_A26 | 7 | B7_N0 |
| ENET1_TX_DATA[0] | Output | PIN_C25 | 7 | B7_N0 |
| ENET1_TX_EN | Output | PIN_B25 | 7 | B7_N0 |
| ENET1_TX_ER | Output | PIN_A25 | 7 | B7_N0 |
| ENETCLK_25 | Input | PIN_A14 | 8 | B8_N0 |

## EX

| Signal | Direction | Location | I/O Bank | VREF Group |
| --- | --- | --- | ---: | --- |
| EX_IO[6] | Bidir | PIN_D9 | 8 | B8_N1 |
| EX_IO[5] | Bidir | PIN_E10 | 8 | B8_N1 |
| EX_IO[4] | Bidir | PIN_F14 | 8 | B8_N0 |
| EX_IO[3] | Bidir | PIN_H14 | 8 | B8_N0 |
| EX_IO[2] | Bidir | PIN_H13 | 8 | B8_N0 |
| EX_IO[1] | Bidir | PIN_J14 | 8 | B8_N0 |
| EX_IO[0] | Bidir | PIN_J10 | 8 | B8_N1 |

## FL

| Signal | Direction | Location | I/O Bank | VREF Group |
| --- | --- | --- | ---: | --- |
| FL_ADDR[22] | Output | PIN_AD11 | 3 | B3_N0 |
| FL_ADDR[21] | Output | PIN_AD10 | 3 | B3_N2 |
| FL_ADDR[20] | Output | PIN_AE10 | 3 | B3_N1 |
| FL_ADDR[19] | Output | PIN_AD12 | 3 | B3_N0 |
| FL_ADDR[18] | Output | PIN_AC12 | 3 | B3_N0 |
| FL_ADDR[17] | Output | PIN_AH12 | 3 | B3_N0 |
| FL_ADDR[16] | Output | PIN_AA8 | 3 | B3_N1 |
| FL_ADDR[15] | Output | PIN_Y10 | 3 | B3_N2 |
| FL_ADDR[14] | Output | PIN_AC8 | 3 | B3_N1 |
| FL_ADDR[13] | Output | PIN_AD8 | 3 | B3_N2 |
| FL_ADDR[12] | Output | PIN_AA10 | 3 | B3_N1 |
| FL_ADDR[11] | Output | PIN_AF9 | 3 | B3_N1 |
| FL_ADDR[10] | Output | PIN_AE9 | 3 | B3_N1 |
| FL_ADDR[9] | Output | PIN_AB10 | 3 | B3_N1 |
| FL_ADDR[8] | Output | PIN_AB12 | 3 | B3_N0 |
| FL_ADDR[7] | Output | PIN_AB13 | 3 | B3_N0 |
| FL_ADDR[6] | Output | PIN_AA12 | 3 | B3_N0 |
| FL_ADDR[5] | Output | PIN_AA13 | 3 | B3_N0 |
| FL_ADDR[4] | Output | PIN_Y12 | 3 | B3_N0 |
| FL_ADDR[3] | Output | PIN_Y14 | 3 | B3_N0 |
| FL_ADDR[2] | Output | PIN_Y13 | 3 | B3_N0 |
| FL_ADDR[1] | Output | PIN_AH7 | 3 | B3_N1 |
| FL_ADDR[0] | Output | PIN_AG12 | 3 | B3_N0 |
| FL_CE_N | Output | PIN_AG7 | 3 | B3_N2 |
| FL_DQ[7] | Bidir | PIN_AF12 | 3 | B3_N1 |
| FL_DQ[6] | Bidir | PIN_AH11 | 3 | B3_N0 |
| FL_DQ[5] | Bidir | PIN_AG11 | 3 | B3_N0 |
| FL_DQ[4] | Bidir | PIN_AF11 | 3 | B3_N1 |
| FL_DQ[3] | Bidir | PIN_AH10 | 3 | B3_N1 |
| FL_DQ[2] | Bidir | PIN_AG10 | 3 | B3_N1 |
| FL_DQ[1] | Bidir | PIN_AF10 | 3 | B3_N1 |
| FL_DQ[0] | Bidir | PIN_AH8 | 3 | B3_N1 |
| FL_OE_N | Output | PIN_AG8 | 3 | B3_N1 |
| FL_RST_N | Output | PIN_AE11 | 3 | B3_N1 |
| FL_RY | Input | PIN_Y1 | 2 | B2_N0 |
| FL_WE_N | Output | PIN_AC10 | 3 | B3_N0 |
| FL_WP_N | Output | PIN_AE12 | 3 | B3_N1 |

## GPIO

| Signal | Direction | Location | I/O Bank | VREF Group |
| --- | --- | --- | ---: | --- |
| GPIO[35] | Bidir | PIN_AG26 | 4 | B4_N0 |
| GPIO[34] | Bidir | PIN_AH23 | 4 | B4_N1 |
| GPIO[33] | Bidir | PIN_AH26 | 4 | B4_N0 |
| GPIO[32] | Bidir | PIN_AF20 | 4 | B4_N1 |
| GPIO[31] | Bidir | PIN_AG23 | 4 | B4_N1 |
| GPIO[30] | Bidir | PIN_AE20 | 4 | B4_N1 |
| GPIO[29] | Bidir | PIN_AF26 | 4 | B4_N1 |
| GPIO[28] | Bidir | PIN_AH22 | 4 | B4_N1 |
| GPIO[27] | Bidir | PIN_AE24 | 4 | B4_N0 |
| GPIO[26] | Bidir | PIN_AG22 | 4 | B4_N1 |
| GPIO[25] | Bidir | PIN_AE25 | 4 | B4_N1 |
| GPIO[24] | Bidir | PIN_AH25 | 4 | B4_N1 |
| GPIO[23] | Bidir | PIN_AD25 | 4 | B4_N0 |
| GPIO[22] | Bidir | PIN_AG25 | 4 | B4_N1 |
| GPIO[21] | Bidir | PIN_AD22 | 4 | B4_N0 |
| GPIO[20] | Bidir | PIN_AF22 | 4 | B4_N0 |
| GPIO[19] | Bidir | PIN_AF21 | 4 | B4_N1 |
| GPIO[18] | Bidir | PIN_AE22 | 4 | B4_N0 |
| GPIO[17] | Bidir | PIN_AC22 | 4 | B4_N0 |
| GPIO[16] | Bidir | PIN_AF25 | 4 | B4_N1 |
| GPIO[15] | Bidir | PIN_AE21 | 4 | B4_N1 |
| GPIO[14] | Bidir | PIN_AF24 | 4 | B4_N1 |
| GPIO[13] | Bidir | PIN_AF15 | 4 | B4_N2 |
| GPIO[12] | Bidir | PIN_AD19 | 4 | B4_N0 |
| GPIO[11] | Bidir | PIN_AF16 | 4 | B4_N2 |
| GPIO[10] | Bidir | PIN_AC19 | 4 | B4_N0 |
| GPIO[9] | Bidir | PIN_AE15 | 4 | B4_N2 |
| GPIO[8] | Bidir | PIN_AD15 | 4 | B4_N2 |
| GPIO[7] | Bidir | PIN_AE16 | 4 | B4_N2 |
| GPIO[6] | Bidir | PIN_AD21 | 4 | B4_N0 |
| GPIO[5] | Bidir | PIN_Y16 | 4 | B4_N0 |
| GPIO[4] | Bidir | PIN_AC21 | 4 | B4_N0 |
| GPIO[3] | Bidir | PIN_Y17 | 4 | B4_N0 |
| GPIO[2] | Bidir | PIN_AB21 | 4 | B4_N0 |
| GPIO[1] | Bidir | PIN_AC15 | 4 | B4_N2 |
| GPIO[0] | Bidir | PIN_AB22 | 4 | B4_N0 |

## HEX

| Signal | Direction | Location | I/O Bank | VREF Group |
| --- | --- | --- | ---: | --- |
| HEX0[6] | Output | PIN_H22 | 6 | B6_N0 |
| HEX0[5] | Output | PIN_J22 | 6 | B6_N0 |
| HEX0[4] | Output | PIN_L25 | 6 | B6_N1 |
| HEX0[3] | Output | PIN_L26 | 6 | B6_N1 |
| HEX0[2] | Output | PIN_E17 | 7 | B7_N2 |
| HEX0[1] | Output | PIN_F22 | 7 | B7_N0 |
| HEX0[0] | Output | PIN_G18 | 7 | B7_N2 |
| HEX1[6] | Output | PIN_U24 | 5 | B5_N0 |
| HEX1[5] | Output | PIN_U23 | 5 | B5_N1 |
| HEX1[4] | Output | PIN_W25 | 5 | B5_N1 |
| HEX1[3] | Output | PIN_W22 | 5 | B5_N0 |
| HEX1[2] | Output | PIN_W21 | 5 | B5_N1 |
| HEX1[1] | Output | PIN_Y22 | 5 | B5_N0 |
| HEX1[0] | Output | PIN_M24 | 6 | B6_N2 |
| HEX2[6] | Output | PIN_W28 | 5 | B5_N1 |
| HEX2[5] | Output | PIN_W27 | 5 | B5_N1 |
| HEX2[4] | Output | PIN_Y26 | 5 | B5_N1 |
| HEX2[3] | Output | PIN_W26 | 5 | B5_N1 |
| HEX2[2] | Output | PIN_Y25 | 5 | B5_N1 |
| HEX2[1] | Output | PIN_AA26 | 5 | B5_N1 |
| HEX2[0] | Output | PIN_AA25 | 5 | B5_N1 |
| HEX3[6] | Output | PIN_Y19 | 4 | B4_N0 |
| HEX3[5] | Output | PIN_AF23 | 4 | B4_N0 |
| HEX3[4] | Output | PIN_AD24 | 4 | B4_N0 |
| HEX3[3] | Output | PIN_AA21 | 4 | B4_N0 |
| HEX3[2] | Output | PIN_AB20 | 4 | B4_N0 |
| HEX3[1] | Output | PIN_U21 | 5 | B5_N0 |
| HEX3[0] | Output | PIN_V21 | 5 | B5_N1 |
| HEX4[6] | Output | PIN_AE18 | 4 | B4_N2 |
| HEX4[5] | Output | PIN_AF19 | 4 | B4_N1 |
| HEX4[4] | Output | PIN_AE19 | 4 | B4_N1 |
| HEX4[3] | Output | PIN_AH21 | 4 | B4_N2 |
| HEX4[2] | Output | PIN_AG21 | 4 | B4_N2 |
| HEX4[1] | Output | PIN_AA19 | 4 | B4_N0 |
| HEX4[0] | Output | PIN_AB19 | 4 | B4_N0 |
| HEX5[6] | Output | PIN_AH18 | 4 | B4_N2 |
| HEX5[5] | Output | PIN_AF18 | 4 | B4_N1 |
| HEX5[4] | Output | PIN_AG19 | 4 | B4_N2 |
| HEX5[3] | Output | PIN_AH19 | 4 | B4_N2 |
| HEX5[2] | Output | PIN_AB18 | 4 | B4_N0 |
| HEX5[1] | Output | PIN_AC18 | 4 | B4_N1 |
| HEX5[0] | Output | PIN_AD18 | 4 | B4_N1 |
| HEX6[6] | Output | PIN_AC17 | 4 | B4_N2 |
| HEX6[5] | Output | PIN_AA15 | 4 | B4_N2 |
| HEX6[4] | Output | PIN_AB15 | 4 | B4_N2 |
| HEX6[3] | Output | PIN_AB17 | 4 | B4_N1 |
| HEX6[2] | Output | PIN_AA16 | 4 | B4_N2 |
| HEX6[1] | Output | PIN_AB16 | 4 | B4_N2 |
| HEX6[0] | Output | PIN_AA17 | 4 | B4_N1 |
| HEX7[6] | Output | PIN_AA14 | 3 | B3_N0 |
| HEX7[5] | Output | PIN_AG18 | 4 | B4_N2 |
| HEX7[4] | Output | PIN_AF17 | 4 | B4_N2 |
| HEX7[3] | Output | PIN_AH17 | 4 | B4_N2 |
| HEX7[2] | Output | PIN_AG17 | 4 | B4_N2 |
| HEX7[1] | Output | PIN_AE17 | 4 | B4_N2 |
| HEX7[0] | Output | PIN_AD17 | 4 | B4_N2 |

## HSMC

| Signal | Direction | Location | I/O Bank | VREF Group |
| --- | --- | --- | ---: | --- |
| HSMC_CLKIN0 | Input | PIN_AH15 | 4 | B4_N2 |
| HSMC_CLKIN_P1 | Input | PIN_J27 | 6 | B6_N2 |
| HSMC_CLKIN_P2 | Input | PIN_Y27 | 5 | B5_N0 |
| HSMC_CLKOUT0 | Output | PIN_AD28 | 5 | B5_N2 |
| HSMC_CLKOUT_P1 | Output | PIN_G23 | 6 | B6_N0 |
| HSMC_CLKOUT_P2 | Output | PIN_V23 | 5 | B5_N1 |
| HSMC_D[3] | Bidir | PIN_AF27 | 5 | B5_N2 |
| HSMC_D[2] | Bidir | PIN_AE27 | 5 | B5_N2 |
| HSMC_D[1] | Bidir | PIN_AE28 | 5 | B5_N2 |
| HSMC_D[0] | Bidir | PIN_AE26 | 5 | B5_N2 |
| HSMC_RX_D_P[16] | Input | PIN_T21 | 5 | B5_N0 |
| HSMC_RX_D_P[15] | Input | PIN_R22 | 5 | B5_N0 |
| HSMC_RX_D_P[14] | Input | PIN_P21 | 5 | B5_N0 |
| HSMC_RX_D_P[13] | Input | PIN_P25 | 6 | B6_N2 |
| HSMC_RX_D_P[12] | Input | PIN_N25 | 6 | B6_N2 |
| HSMC_RX_D_P[11] | Input | PIN_L21 | 6 | B6_N0 |
| HSMC_RX_D_P[10] | Input | PIN_U25 | 5 | B5_N0 |
| HSMC_RX_D_P[9] | Input | PIN_T25 | 5 | B5_N0 |
| HSMC_RX_D_P[8] | Input | PIN_R25 | 5 | B5_N0 |
| HSMC_RX_D_P[7] | Input | PIN_M25 | 6 | B6_N2 |
| HSMC_RX_D_P[6] | Input | PIN_L23 | 6 | B6_N1 |
| HSMC_RX_D_P[5] | Input | PIN_K25 | 6 | B6_N1 |
| HSMC_RX_D_P[4] | Input | PIN_H25 | 6 | B6_N1 |
| HSMC_RX_D_P[3] | Input | PIN_G25 | 6 | B6_N0 |
| HSMC_RX_D_P[2] | Input | PIN_F26 | 6 | B6_N1 |
| HSMC_RX_D_P[1] | Input | PIN_D26 | 6 | B6_N0 |
| HSMC_RX_D_P[0] | Input | PIN_F24 | 6 | B6_N0 |
| HSMC_TX_D_P[16] | Output | PIN_U22 | 5 | B5_N0 |
| HSMC_TX_D_P[15] | Output | PIN_V27 | 5 | B5_N1 |
| HSMC_TX_D_P[14] | Output | PIN_U27 | 5 | B5_N0 |
| HSMC_TX_D_P[13] | Output | PIN_R27 | 5 | B5_N0 |
| HSMC_TX_D_P[12] | Output | PIN_V25 | 5 | B5_N1 |
| HSMC_TX_D_P[11] | Output | PIN_L27 | 6 | B6_N2 |
| HSMC_TX_D_P[10] | Output | PIN_J25 | 6 | B6_N1 |
| HSMC_TX_D_P[9] | Output | PIN_P27 | 6 | B6_N2 |
| HSMC_TX_D_P[8] | Output | PIN_J23 | 6 | B6_N0 |
| HSMC_TX_D_P[7] | Output | PIN_H23 | 6 | B6_N0 |
| HSMC_TX_D_P[6] | Output | PIN_K21 | 6 | B6_N0 |
| HSMC_TX_D_P[5] | Output | PIN_M27 | 6 | B6_N2 |
| HSMC_TX_D_P[4] | Output | PIN_K27 | 6 | B6_N1 |
| HSMC_TX_D_P[3] | Output | PIN_G27 | 6 | B6_N1 |
| HSMC_TX_D_P[2] | Output | PIN_F27 | 6 | B6_N1 |
| HSMC_TX_D_P[1] | Output | PIN_E27 | 6 | B6_N1 |
| HSMC_TX_D_P[0] | Output | PIN_D27 | 6 | B6_N0 |
| HSMC_CLKIN_N1 | Unknown | PIN_J28 | 6 | B6_N2 |
| HSMC_CLKIN_N2 | Unknown | PIN_Y28 | 5 | B5_N0 |
| HSMC_TX_D_N[0] | Unknown | PIN_D28 | 6 | B6_N0 |
| HSMC_RX_D_N[0] | Unknown | PIN_F25 | 6 | B6_N0 |
| HSMC_RX_D_N[1] | Unknown | PIN_C27 | 6 | B6_N0 |
| HSMC_TX_D_N[1] | Unknown | PIN_E28 | 6 | B6_N1 |
| HSMC_TX_D_N[2] | Unknown | PIN_F28 | 6 | B6_N1 |
| HSMC_RX_D_N[2] | Unknown | PIN_E26 | 6 | B6_N1 |
| HSMC_TX_D_N[3] | Unknown | PIN_G28 | 6 | B6_N1 |
| HSMC_RX_D_N[3] | Unknown | PIN_G26 | 6 | B6_N0 |
| HSMC_TX_D_N[4] | Unknown | PIN_K28 | 6 | B6_N1 |
| HSMC_RX_D_N[4] | Unknown | PIN_H26 | 6 | B6_N1 |
| HSMC_TX_D_N[5] | Unknown | PIN_M28 | 6 | B6_N2 |
| HSMC_RX_D_N[5] | Unknown | PIN_K26 | 6 | B6_N1 |
| HSMC_TX_D_N[6] | Unknown | PIN_K22 | 6 | B6_N0 |
| HSMC_RX_D_N[6] | Unknown | PIN_L24 | 6 | B6_N2 |
| HSMC_TX_D_N[7] | Unknown | PIN_H24 | 6 | B6_N0 |
| HSMC_RX_D_N[7] | Unknown | PIN_M26 | 6 | B6_N2 |
| HSMC_TX_D_N[8] | Unknown | PIN_J24 | 6 | B6_N0 |
| HSMC_RX_D_N[8] | Unknown | PIN_R26 | 5 | B5_N0 |
| HSMC_TX_D_N[9] | Unknown | PIN_P28 | 6 | B6_N2 |
| HSMC_RX_D_N[9] | Unknown | PIN_T26 | 5 | B5_N0 |
| HSMC_TX_D_N[10] | Unknown | PIN_J26 | 6 | B6_N1 |
| HSMC_RX_D_N[10] | Unknown | PIN_U26 | 5 | B5_N0 |
| HSMC_TX_D_N[11] | Unknown | PIN_L28 | 6 | B6_N2 |
| HSMC_RX_D_N[11] | Unknown | PIN_L22 | 6 | B6_N0 |
| HSMC_TX_D_N[12] | Unknown | PIN_V26 | 5 | B5_N1 |
| HSMC_RX_D_N[12] | Unknown | PIN_N26 | 6 | B6_N2 |
| HSMC_TX_D_N[13] | Unknown | PIN_R28 | 5 | B5_N0 |
| HSMC_RX_D_N[13] | Unknown | PIN_P26 | 6 | B6_N2 |
| HSMC_TX_D_N[14] | Unknown | PIN_U28 | 5 | B5_N0 |
| HSMC_RX_D_N[14] | Unknown | PIN_R21 | 5 | B5_N0 |
| HSMC_TX_D_N[15] | Unknown | PIN_V28 | 5 | B5_N1 |
| HSMC_RX_D_N[15] | Unknown | PIN_R23 | 5 | B5_N0 |
| HSMC_TX_D_N[16] | Unknown | PIN_V22 | 5 | B5_N1 |
| HSMC_RX_D_N[16] | Unknown | PIN_T22 | 5 | B5_N0 |
| HSMC_CLKOUT_N2 | Unknown | PIN_V24 | 5 | B5_N1 |
| HSMC_CLKOUT_N1 | Unknown | PIN_G24 | 6 | B6_N0 |

## I2C

| Signal | Direction | Location | I/O Bank | VREF Group |
| --- | --- | --- | ---: | --- |
| I2C_SCLK | Output | PIN_B7 | 8 | B8_N1 |
| I2C_SDAT | Bidir | PIN_A8 | 8 | B8_N1 |
| IRDA_RXD | Input | PIN_Y15 | 3 | B3_N0 |

## KEY

| Signal | Direction | Location | I/O Bank | VREF Group |
| --- | --- | --- | ---: | --- |
| KEY[3] | Input | PIN_R24 | 5 | B5_N0 |
| KEY[2] | Input | PIN_N21 | 6 | B6_N2 |
| KEY[1] | Input | PIN_M21 | 6 | B6_N1 |
| KEY[0] | Input | PIN_M23 | 6 | B6_N2 |

## LCD

| Signal | Direction | Location | I/O Bank | VREF Group |
| --- | --- | --- | ---: | --- |
| LCD_BLON | Output | PIN_L6 | 1 | B1_N2 |
| LCD_DATA[7] | Bidir | PIN_M5 | 1 | B1_N2 |
| LCD_DATA[6] | Bidir | PIN_M3 | 1 | B1_N1 |
| LCD_DATA[5] | Bidir | PIN_K2 | 1 | B1_N1 |
| LCD_DATA[4] | Bidir | PIN_K1 | 1 | B1_N1 |
| LCD_DATA[3] | Bidir | PIN_K7 | 1 | B1_N1 |
| LCD_DATA[2] | Bidir | PIN_L2 | 1 | B1_N2 |
| LCD_DATA[1] | Bidir | PIN_L1 | 1 | B1_N2 |
| LCD_DATA[0] | Bidir | PIN_L3 | 1 | B1_N1 |
| LCD_EN | Output | PIN_L4 | 1 | B1_N1 |
| LCD_ON | Output | PIN_L5 | 1 | B1_N1 |
| LCD_RS | Output | PIN_M2 | 1 | B1_N2 |
| LCD_RW | Output | PIN_M1 | 1 | B1_N2 |

## LED

| Signal | Direction | Location | I/O Bank | VREF Group |
| --- | --- | --- | ---: | --- |
| LEDG[8] | Output | PIN_F17 | 7 | B7_N2 |
| LEDG[7] | Output | PIN_G21 | 7 | B7_N1 |
| LEDG[6] | Output | PIN_G22 | 7 | B7_N2 |
| LEDG[5] | Output | PIN_G20 | 7 | B7_N1 |
| LEDG[4] | Output | PIN_H21 | 7 | B7_N2 |
| LEDG[3] | Output | PIN_E24 | 7 | B7_N1 |
| LEDG[2] | Output | PIN_E25 | 7 | B7_N1 |
| LEDG[1] | Output | PIN_E22 | 7 | B7_N0 |
| LEDG[0] | Output | PIN_E21 | 7 | B7_N0 |
| LEDR[17] | Output | PIN_H15 | 7 | B7_N2 |
| LEDR[16] | Output | PIN_G16 | 7 | B7_N2 |
| LEDR[15] | Output | PIN_G15 | 7 | B7_N2 |
| LEDR[14] | Output | PIN_F15 | 7 | B7_N2 |
| LEDR[13] | Output | PIN_H17 | 7 | B7_N2 |
| LEDR[12] | Output | PIN_J16 | 7 | B7_N2 |
| LEDR[11] | Output | PIN_H16 | 7 | B7_N2 |
| LEDR[10] | Output | PIN_J15 | 7 | B7_N2 |
| LEDR[9] | Output | PIN_G17 | 7 | B7_N1 |
| LEDR[8] | Output | PIN_J17 | 7 | B7_N2 |
| LEDR[7] | Output | PIN_H19 | 7 | B7_N2 |
| LEDR[6] | Output | PIN_J19 | 7 | B7_N2 |
| LEDR[5] | Output | PIN_E18 | 7 | B7_N1 |
| LEDR[4] | Output | PIN_F18 | 7 | B7_N1 |
| LEDR[3] | Output | PIN_F21 | 7 | B7_N0 |
| LEDR[2] | Output | PIN_E19 | 7 | B7_N0 |
| LEDR[1] | Output | PIN_F19 | 7 | B7_N0 |
| LEDR[0] | Output | PIN_G19 | 7 | B7_N2 |

## OTG

| Signal | Direction | Location | I/O Bank | VREF Group |
| --- | --- | --- | ---: | --- |
| OTG_ADDR[1] | Output | PIN_C3 | 8 | B8_N2 |
| OTG_ADDR[0] | Output | PIN_H7 | 1 | B1_N0 |
| OTG_CS_N | Output | PIN_A3 | 8 | B8_N2 |
| OTG_DACK_N[1] | Output | PIN_D4 | 8 | B8_N2 |
| OTG_DACK_N[0] | Output | PIN_C4 | 8 | B8_N2 |
| OTG_DATA[15] | Bidir | PIN_G4 | 1 | B1_N0 |
| OTG_DATA[14] | Bidir | PIN_F3 | 1 | B1_N0 |
| OTG_DATA[13] | Bidir | PIN_F1 | 1 | B1_N1 |
| OTG_DATA[12] | Bidir | PIN_G3 | 1 | B1_N0 |
| OTG_DATA[11] | Bidir | PIN_G2 | 1 | B1_N1 |
| OTG_DATA[10] | Bidir | PIN_G1 | 1 | B1_N1 |
| OTG_DATA[9] | Bidir | PIN_H4 | 1 | B1_N0 |
| OTG_DATA[8] | Bidir | PIN_H3 | 1 | B1_N0 |
| OTG_DATA[7] | Bidir | PIN_H6 | 1 | B1_N0 |
| OTG_DATA[6] | Bidir | PIN_J7 | 1 | B1_N1 |
| OTG_DATA[5] | Bidir | PIN_J3 | 1 | B1_N1 |
| OTG_DATA[4] | Bidir | PIN_J4 | 1 | B1_N1 |
| OTG_DATA[3] | Bidir | PIN_K3 | 1 | B1_N1 |
| OTG_DATA[2] | Bidir | PIN_J5 | 1 | B1_N1 |
| OTG_DATA[1] | Bidir | PIN_K4 | 1 | B1_N1 |
| OTG_DATA[0] | Bidir | PIN_J6 | 1 | B1_N1 |
| OTG_DREQ[1] | Input | PIN_B4 | 8 | B8_N2 |
| OTG_DREQ[0] | Input | PIN_J1 | 1 | B1_N2 |
| OTG_FSPEED | Bidir | PIN_C6 | 8 | B8_N2 |
| OTG_INT[1] | Input | PIN_D5 | 8 | B8_N2 |
| OTG_INT[0] | Input | PIN_A6 | 8 | B8_N1 |
| OTG_LSPEED | Bidir | PIN_B6 | 8 | B8_N1 |
| OTG_RD_N | Output | PIN_B3 | 8 | B8_N2 |
| OTG_RST_N | Output | PIN_C5 | 8 | B8_N2 |
| OTG_WR_N | Output | PIN_A4 | 8 | B8_N2 |

## PS2

| Signal | Direction | Location | I/O Bank | VREF Group |
| --- | --- | --- | ---: | --- |
| PS2_CLK | Bidir | PIN_G6 | 1 | B1_N0 |
| PS2_CLK2 | Bidir | PIN_G5 | 1 | B1_N0 |
| PS2_DAT | Bidir | PIN_H5 | 1 | B1_N1 |
| PS2_DAT2 | Bidir | PIN_F5 | 1 | B1_N0 |

## SD

| Signal | Direction | Location | I/O Bank | VREF Group |
| --- | --- | --- | ---: | --- |
| SD_CLK | Output | PIN_AE13 | 3 | B3_N0 |
| SD_CMD | Bidir | PIN_AD14 | 3 | B3_N0 |
| SD_DAT[3] | Bidir | PIN_AC14 | 3 | B3_N0 |
| SD_DAT[2] | Bidir | PIN_AB14 | 3 | B3_N0 |
| SD_DAT[1] | Bidir | PIN_AF13 | 3 | B3_N0 |
| SD_DAT[0] | Bidir | PIN_AE14 | 3 | B3_N0 |
| SD_WP_N | Input | PIN_AF14 | 3 | B3_N0 |

## SMA

| Signal | Direction | Location | I/O Bank | VREF Group |
| --- | --- | --- | ---: | --- |
| SMA_CLKIN | Input | PIN_AH14 | 3 | B3_N0 |
| SMA_CLKOUT | Output | PIN_AE23 | 4 | B4_N0 |

## SRAM

| Signal | Direction | Location | I/O Bank | VREF Group |
| --- | --- | --- | ---: | --- |
| SRAM_ADDR[19] | Output | PIN_T8 | 2 | B2_N1 |
| SRAM_ADDR[18] | Output | PIN_AB8 | 3 | B3_N2 |
| SRAM_ADDR[17] | Output | PIN_AB9 | 3 | B3_N2 |
| SRAM_ADDR[16] | Output | PIN_AC11 | 3 | B3_N0 |
| SRAM_ADDR[15] | Output | PIN_AB11 | 3 | B3_N1 |
| SRAM_ADDR[14] | Output | PIN_AA4 | 2 | B2_N1 |
| SRAM_ADDR[13] | Output | PIN_AC3 | 2 | B2_N1 |
| SRAM_ADDR[12] | Output | PIN_AB4 | 2 | B2_N2 |
| SRAM_ADDR[11] | Output | PIN_AD3 | 2 | B2_N1 |
| SRAM_ADDR[10] | Output | PIN_AF2 | 2 | B2_N2 |
| SRAM_ADDR[9] | Output | PIN_T7 | 2 | B2_N0 |
| SRAM_ADDR[8] | Output | PIN_AF5 | 3 | B3_N2 |
| SRAM_ADDR[7] | Output | PIN_AC5 | 2 | B2_N2 |
| SRAM_ADDR[6] | Output | PIN_AB5 | 2 | B2_N2 |
| SRAM_ADDR[5] | Output | PIN_AE6 | 3 | B3_N2 |
| SRAM_ADDR[4] | Output | PIN_AB6 | 2 | B2_N2 |
| SRAM_ADDR[3] | Output | PIN_AC7 | 3 | B3_N2 |
| SRAM_ADDR[2] | Output | PIN_AE7 | 3 | B3_N1 |
| SRAM_ADDR[1] | Output | PIN_AD7 | 3 | B3_N2 |
| SRAM_ADDR[0] | Output | PIN_AB7 | 3 | B3_N1 |
| SRAM_CE_N | Output | PIN_AF8 | 3 | B3_N1 |
| SRAM_DQ[15] | Bidir | PIN_AG3 | 3 | B3_N2 |
| SRAM_DQ[14] | Bidir | PIN_AF3 | 3 | B3_N2 |
| SRAM_DQ[13] | Bidir | PIN_AE4 | 3 | B3_N2 |
| SRAM_DQ[12] | Bidir | PIN_AE3 | 2 | B2_N2 |
| SRAM_DQ[11] | Bidir | PIN_AE1 | 2 | B2_N1 |
| SRAM_DQ[10] | Bidir | PIN_AE2 | 2 | B2_N1 |
| SRAM_DQ[9] | Bidir | PIN_AD2 | 2 | B2_N1 |
| SRAM_DQ[8] | Bidir | PIN_AD1 | 2 | B2_N1 |
| SRAM_DQ[7] | Bidir | PIN_AF7 | 3 | B3_N1 |
| SRAM_DQ[6] | Bidir | PIN_AH6 | 3 | B3_N2 |
| SRAM_DQ[5] | Bidir | PIN_AG6 | 3 | B3_N2 |
| SRAM_DQ[4] | Bidir | PIN_AF6 | 3 | B3_N2 |
| SRAM_DQ[3] | Bidir | PIN_AH4 | 3 | B3_N2 |
| SRAM_DQ[2] | Bidir | PIN_AG4 | 3 | B3_N2 |
| SRAM_DQ[1] | Bidir | PIN_AF4 | 3 | B3_N2 |
| SRAM_DQ[0] | Bidir | PIN_AH3 | 3 | B3_N2 |
| SRAM_LB_N | Output | PIN_AD4 | 3 | B3_N2 |
| SRAM_OE_N | Output | PIN_AD5 | 3 | B3_N2 |
| SRAM_UB_N | Output | PIN_AC4 | 2 | B2_N2 |
| SRAM_WE_N | Output | PIN_AE8 | 3 | B3_N1 |

## SW

| Signal | Direction | Location | I/O Bank | VREF Group |
| --- | --- | --- | ---: | --- |
| SW[17] | Input | PIN_Y23 | 5 | B5_N2 |
| SW[16] | Input | PIN_Y24 | 5 | B5_N2 |
| SW[15] | Input | PIN_AA22 | 5 | B5_N2 |
| SW[14] | Input | PIN_AA23 | 5 | B5_N2 |
| SW[13] | Input | PIN_AA24 | 5 | B5_N2 |
| SW[12] | Input | PIN_AB23 | 5 | B5_N2 |
| SW[11] | Input | PIN_AB24 | 5 | B5_N2 |
| SW[10] | Input | PIN_AC24 | 5 | B5_N2 |
| SW[9] | Input | PIN_AB25 | 5 | B5_N1 |
| SW[8] | Input | PIN_AC25 | 5 | B5_N2 |
| SW[7] | Input | PIN_AB26 | 5 | B5_N1 |
| SW[6] | Input | PIN_AD26 | 5 | B5_N2 |
| SW[5] | Input | PIN_AC26 | 5 | B5_N2 |
| SW[4] | Input | PIN_AB27 | 5 | B5_N1 |
| SW[3] | Input | PIN_AD27 | 5 | B5_N2 |
| SW[2] | Input | PIN_AC27 | 5 | B5_N2 |
| SW[1] | Input | PIN_AC28 | 5 | B5_N2 |
| SW[0] | Input | PIN_AB28 | 5 | B5_N1 |

## TD

| Signal | Direction | Location | I/O Bank | VREF Group |
| --- | --- | --- | ---: | --- |
| TD_CLK27 | Input | PIN_B14 | 8 | B8_N0 |
| TD_DATA[7] | Input | PIN_F7 | 8 | B8_N2 |
| TD_DATA[6] | Input | PIN_E7 | 8 | B8_N2 |
| TD_DATA[5] | Input | PIN_D6 | 8 | B8_N2 |
| TD_DATA[4] | Input | PIN_D7 | 8 | B8_N2 |
| TD_DATA[3] | Input | PIN_C7 | 8 | B8_N2 |
| TD_DATA[2] | Input | PIN_D8 | 8 | B8_N2 |
| TD_DATA[1] | Input | PIN_A7 | 8 | B8_N1 |
| TD_DATA[0] | Input | PIN_E8 | 8 | B8_N2 |
| TD_HS | Input | PIN_E5 | 8 | B8_N2 |
| TD_RESET_N | Output | PIN_G7 | 8 | B8_N2 |
| TD_VS | Input | PIN_E4 | 8 | B8_N2 |

## UART

| Signal | Direction | Location | I/O Bank | VREF Group |
| --- | --- | --- | ---: | --- |
| UART_CTS | Output | PIN_G14 | 8 | B8_N0 |
| UART_RTS | Input | PIN_J13 | 8 | B8_N0 |
| UART_RXD | Input | PIN_G12 | 8 | B8_N1 |
| UART_TXD | Output | PIN_G9 | 8 | B8_N2 |

## VGA

| Signal | Direction | Location | I/O Bank | VREF Group |
| --- | --- | --- | ---: | --- |
| VGA_B[7] | Output | PIN_D12 | 8 | B8_N0 |
| VGA_B[6] | Output | PIN_D11 | 8 | B8_N1 |
| VGA_B[5] | Output | PIN_C12 | 8 | B8_N0 |
| VGA_B[4] | Output | PIN_A11 | 8 | B8_N0 |
| VGA_B[3] | Output | PIN_B11 | 8 | B8_N0 |
| VGA_B[2] | Output | PIN_C11 | 8 | B8_N1 |
| VGA_B[1] | Output | PIN_A10 | 8 | B8_N0 |
| VGA_B[0] | Output | PIN_B10 | 8 | B8_N0 |
| VGA_BLANK_N | Output | PIN_F11 | 8 | B8_N1 |
| VGA_CLK | Output | PIN_A12 | 8 | B8_N0 |
| VGA_G[7] | Output | PIN_C9 | 8 | B8_N1 |
| VGA_G[6] | Output | PIN_F10 | 8 | B8_N1 |
| VGA_G[5] | Output | PIN_B8 | 8 | B8_N1 |
| VGA_G[4] | Output | PIN_C8 | 8 | B8_N1 |
| VGA_G[3] | Output | PIN_H12 | 8 | B8_N1 |
| VGA_G[2] | Output | PIN_F8 | 8 | B8_N2 |
| VGA_G[1] | Output | PIN_G11 | 8 | B8_N1 |
| VGA_G[0] | Output | PIN_G8 | 8 | B8_N2 |
| VGA_HS | Output | PIN_G13 | 8 | B8_N0 |
| VGA_R[7] | Output | PIN_H10 | 8 | B8_N1 |
| VGA_R[6] | Output | PIN_H8 | 8 | B8_N2 |
| VGA_R[5] | Output | PIN_J12 | 8 | B8_N0 |
| VGA_R[4] | Output | PIN_G10 | 8 | B8_N1 |
| VGA_R[3] | Output | PIN_F12 | 8 | B8_N1 |
| VGA_R[2] | Output | PIN_D10 | 8 | B8_N1 |
| VGA_R[1] | Output | PIN_E11 | 8 | B8_N1 |
| VGA_R[0] | Output | PIN_E12 | 8 | B8_N1 |
| VGA_SYNC_N | Output | PIN_C10 | 8 | B8_N0 |
| VGA_VS | Output | PIN_C13 | 8 | B8_N0 |

