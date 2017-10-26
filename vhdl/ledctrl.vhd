-- Adafruit RGB LED Matrix Display Driver
-- Finite state machine to control the LED matrix hardware
-- 
-- Copyright (c) 2012 Brian Nezvadovitz <http://nezzen.net>
-- This software is distributed under the terms of the MIT License shown below.
-- 
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to
-- deal in the Software without restriction, including without limitation the
-- rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
-- sell copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
-- 
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
-- 
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
-- FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
-- IN THE SOFTWARE.

-- For some great documentation on how the RGB LED panel works, see this page:
-- http://www.rayslogic.com/propeller/Programming/AdafruitRGB/AdafruitRGB.htm
-- or this page
-- http://www.ladyada.net/wiki/tutorials/products/rgbledmatrix/index.html#how_the_matrix_works

  library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity ledctrl is
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;
        sel0     : in  std_logic;
		  sel1     : in  std_logic;
        -- LED Panel IO
        clk_out  : out std_logic;
        rgbUU    : out std_logic_vector(2 downto 0);
        rgbUL    : out std_logic_vector(2 downto 0);
        rgbLU    : out std_logic_vector(2 downto 0);
        rgbLL    : out std_logic_vector(2 downto 0);
        led_addr : out std_logic_vector(3 downto 0);
        lat      : out std_logic;
        oe       : out std_logic;
        -- Memory IO
        addr     : out std_logic_vector(11 downto 0);
        dataUU   : in  std_logic_vector(23 downto 0);
        dataUL   : in  std_logic_vector(23 downto 0);
        dataLU   : in  std_logic_vector(23 downto 0);
        dataLL   : in  std_logic_vector(23 downto 0)
        );
end ledctrl;
architecture bhv of ledctrl is
    -- Internal signals
    
    -- Essential state machine signals
    type STATE_TYPE is (INIT, READ_PIXEL_DATA, INCR_RAM_ADDR, INCR_LED_ADDR, LWAIT, LATCH);
    signal state, next_state : STATE_TYPE;
    
    -- State machine signals
    signal col_count, next_col_count : unsigned(7 downto 0);
    signal bpp_count, next_bpp_count : unsigned(2 downto 0);
    signal dly_timer, next_dly_timer : unsigned(14 downto 0);
    signal s_led_addr, next_led_addr : std_logic_vector(3 downto 0);
    signal s_rgbUU, next_rgbUU, s_rgbUL, next_rgbUL : std_logic_vector(2 downto 0);
    signal s_rgbLU, next_rgbLU, s_rgbLL, next_rgbLL : std_logic_vector(2 downto 0);
    signal s_oe, s_lat, s_clk_out : std_logic;
begin
    -- Breakout internal signals to the output port
    led_addr <= not s_led_addr;
    addr <= std_logic_vector(unsigned(s_led_addr) + 1) & std_logic_vector(col_count);
    rgbUU <= s_rgbUU;
    rgbUL <= s_rgbUL;
    rgbLU <= s_rgbLU;
    rgbLL <= s_rgbLL;
    oe <= s_oe;
    lat <= s_lat;
    clk_out <= s_clk_out;

    -- State register
    process(rst, clk)
    begin
        if(rst = '1') then
            state <= INIT;
            col_count <= to_unsigned(192, next_col_count'length);
            bpp_count <= (others => '0');
            dly_timer <= (others => '0');
            s_led_addr <= (others => '0');
            s_rgbUU <= (others => '0');
            s_rgbUL <= (others => '0');
            s_rgbLU <= (others => '0');
            s_rgbLL <= (others => '0');
        elsif(rising_edge(clk)) then
            state <= next_state;
            col_count <= next_col_count;
            bpp_count <= next_bpp_count;
            dly_timer <= next_dly_timer;
            s_led_addr <= next_led_addr;
            s_rgbUU <= next_rgbUU;
            s_rgbUL <= next_rgbUL;
            s_rgbLU <= next_rgbLU;
            s_rgbLL <= next_rgbLL;
        end if;
    end process;
    
    -- Next-state logic
    process(state,col_count,bpp_count,dly_timer,s_led_addr,s_rgbUU,s_rgbUL,s_rgbLU,s_rgbLL,dataUU, dataUL, dataLU,dataLL,sel0,sel1) is
        -- Internal breakouts
        variable UU_r, UU_g, UU_b : unsigned(7 downto 0); -- brightness bytes
        variable UL_r, UL_g, UL_b : unsigned(7 downto 0); -- brightness bytes
        variable LU_r, LU_g, LU_b : unsigned(7 downto 0); -- brightness bytes
        variable LL_r, LL_g, LL_b : unsigned(7 downto 0); -- brightness bytes
        type gamma_table_t is array(0 to 255) of unsigned(7 downto 0);
        constant gamma_table : gamma_table_t := (
            0   => to_unsigned(0, 8),
            1   => to_unsigned(0, 8),
            2   => to_unsigned(0, 8),
            3   => to_unsigned(0, 8),
            4   => to_unsigned(0, 8),
            5   => to_unsigned(0, 8),
            6   => to_unsigned(0, 8),
            7   => to_unsigned(0, 8),
            8   => to_unsigned(0, 8),
            9   => to_unsigned(0, 8),
            10  => to_unsigned(0, 8),
            11  => to_unsigned(0, 8),
            12  => to_unsigned(0, 8),
            13  => to_unsigned(0, 8),
            14  => to_unsigned(0, 8),
            15  => to_unsigned(0, 8),
            16  => to_unsigned(0, 8),
            17  => to_unsigned(0, 8),
            18  => to_unsigned(0, 8),
            19  => to_unsigned(0, 8),
            20  => to_unsigned(0, 8),
            21  => to_unsigned(0, 8),
            22  => to_unsigned(1, 8),
            23  => to_unsigned(1, 8),
            24  => to_unsigned(1, 8),
            25  => to_unsigned(1, 8),
            26  => to_unsigned(1, 8),
            27  => to_unsigned(1, 8),
            28  => to_unsigned(1, 8),
            29  => to_unsigned(2, 8),
            30  => to_unsigned(2, 8),
            31  => to_unsigned(2, 8),
            32  => to_unsigned(2, 8),
            33  => to_unsigned(2, 8),
            34  => to_unsigned(2, 8),
            35  => to_unsigned(3, 8),
            36  => to_unsigned(3, 8),
            37  => to_unsigned(3, 8),
            38  => to_unsigned(3, 8),
            39  => to_unsigned(3, 8),
            40  => to_unsigned(4, 8),
            41  => to_unsigned(4, 8),
            42  => to_unsigned(4, 8),
            43  => to_unsigned(4, 8),
            44  => to_unsigned(5, 8),
            45  => to_unsigned(5, 8),
            46  => to_unsigned(5, 8),
            47  => to_unsigned(5, 8),
            48  => to_unsigned(6, 8),
            49  => to_unsigned(6, 8),
            50  => to_unsigned(6, 8),
            51  => to_unsigned(7, 8),
            52  => to_unsigned(7, 8),
            53  => to_unsigned(7, 8),
            54  => to_unsigned(8, 8),
            55  => to_unsigned(8, 8),
            56  => to_unsigned(8, 8),
            57  => to_unsigned(9, 8),
            58  => to_unsigned(9, 8),
            59  => to_unsigned(9, 8),
            60  => to_unsigned(10, 8),
            61  => to_unsigned(10, 8),
            62  => to_unsigned(11, 8),
            63  => to_unsigned(11, 8),
            64  => to_unsigned(11, 8),
            65  => to_unsigned(12, 8),
            66  => to_unsigned(12, 8),
            67  => to_unsigned(13, 8),
            68  => to_unsigned(13, 8),
            69  => to_unsigned(13, 8),
            70  => to_unsigned(14, 8),
            71  => to_unsigned(14, 8),
            72  => to_unsigned(15, 8),
            73  => to_unsigned(15, 8),
            74  => to_unsigned(16, 8),
            75  => to_unsigned(16, 8),
            76  => to_unsigned(17, 8),
            77  => to_unsigned(17, 8),
            78  => to_unsigned(18, 8),
            79  => to_unsigned(18, 8),
            80  => to_unsigned(19, 8),
            81  => to_unsigned(19, 8),
            82  => to_unsigned(20, 8),
            83  => to_unsigned(21, 8),
            84  => to_unsigned(21, 8),
            85  => to_unsigned(22, 8),
            86  => to_unsigned(22, 8),
            87  => to_unsigned(23, 8),
            88  => to_unsigned(23, 8),
            89  => to_unsigned(24, 8),
            90  => to_unsigned(25, 8),
            91  => to_unsigned(25, 8),
            92  => to_unsigned(26, 8),
            93  => to_unsigned(27, 8),
            94  => to_unsigned(27, 8),
            95  => to_unsigned(28, 8),
            96  => to_unsigned(29, 8),
            97  => to_unsigned(29, 8),
            98  => to_unsigned(30, 8),
            99  => to_unsigned(31, 8),
            100 => to_unsigned(31, 8),
            101 => to_unsigned(32, 8),
            102 => to_unsigned(33, 8),
            103 => to_unsigned(34, 8),
            104 => to_unsigned(34, 8),
            105 => to_unsigned(35, 8),
            106 => to_unsigned(36, 8),
            107 => to_unsigned(37, 8),
            108 => to_unsigned(37, 8),
            109 => to_unsigned(38, 8),
            110 => to_unsigned(39, 8),
            111 => to_unsigned(40, 8),
            112 => to_unsigned(40, 8),
            113 => to_unsigned(41, 8),
            114 => to_unsigned(42, 8),
            115 => to_unsigned(43, 8),
            116 => to_unsigned(44, 8),
            117 => to_unsigned(45, 8),
            118 => to_unsigned(46, 8),
            119 => to_unsigned(46, 8),
            120 => to_unsigned(47, 8),
            121 => to_unsigned(48, 8),
            122 => to_unsigned(49, 8),
            123 => to_unsigned(50, 8),
            124 => to_unsigned(51, 8),
            125 => to_unsigned(52, 8),
            126 => to_unsigned(53, 8),
            127 => to_unsigned(54, 8),
            128 => to_unsigned(55, 8),
            129 => to_unsigned(56, 8),
            130 => to_unsigned(57, 8),
            131 => to_unsigned(58, 8),
            132 => to_unsigned(59, 8),
            133 => to_unsigned(60, 8),
            134 => to_unsigned(61, 8),
            135 => to_unsigned(62, 8),
            136 => to_unsigned(63, 8),
            137 => to_unsigned(64, 8),
            138 => to_unsigned(65, 8),
            139 => to_unsigned(66, 8),
            140 => to_unsigned(67, 8),
            141 => to_unsigned(68, 8),
            142 => to_unsigned(69, 8),
            143 => to_unsigned(70, 8),
            144 => to_unsigned(71, 8),
            145 => to_unsigned(72, 8),
            146 => to_unsigned(73, 8),
            147 => to_unsigned(74, 8),
            148 => to_unsigned(76, 8),
            149 => to_unsigned(77, 8),
            150 => to_unsigned(78, 8),
            151 => to_unsigned(79, 8),
            152 => to_unsigned(80, 8),
            153 => to_unsigned(81, 8),
            154 => to_unsigned(83, 8),
            155 => to_unsigned(84, 8),
            156 => to_unsigned(85, 8),
            157 => to_unsigned(86, 8),
            158 => to_unsigned(88, 8),
            159 => to_unsigned(89, 8),
            160 => to_unsigned(90, 8),
            161 => to_unsigned(91, 8),
            162 => to_unsigned(93, 8),
            163 => to_unsigned(94, 8),
            164 => to_unsigned(95, 8),
            165 => to_unsigned(96, 8),
            166 => to_unsigned(98, 8),
            167 => to_unsigned(99, 8),
            168 => to_unsigned(100, 8),
            169 => to_unsigned(102, 8),
            170 => to_unsigned(103, 8),
            171 => to_unsigned(104, 8),
            172 => to_unsigned(106, 8),
            173 => to_unsigned(107, 8),
            174 => to_unsigned(109, 8),
            175 => to_unsigned(110, 8),
            176 => to_unsigned(111, 8),
            177 => to_unsigned(113, 8),
            178 => to_unsigned(114, 8),
            179 => to_unsigned(116, 8),
            180 => to_unsigned(117, 8),
            181 => to_unsigned(119, 8),
            182 => to_unsigned(120, 8),
            183 => to_unsigned(121, 8),
            184 => to_unsigned(123, 8),
            185 => to_unsigned(124, 8),
            186 => to_unsigned(126, 8),
            187 => to_unsigned(128, 8),
            188 => to_unsigned(129, 8),
            189 => to_unsigned(131, 8),
            190 => to_unsigned(132, 8),
            191 => to_unsigned(134, 8),
            192 => to_unsigned(135, 8),
            193 => to_unsigned(137, 8),
            194 => to_unsigned(138, 8),
            195 => to_unsigned(140, 8),
            196 => to_unsigned(142, 8),
            197 => to_unsigned(143, 8),
            198 => to_unsigned(145, 8),
            199 => to_unsigned(146, 8),
            200 => to_unsigned(148, 8),
            201 => to_unsigned(150, 8),
            202 => to_unsigned(151, 8),
            203 => to_unsigned(153, 8),
            204 => to_unsigned(155, 8),
            205 => to_unsigned(157, 8),
            206 => to_unsigned(158, 8),
            207 => to_unsigned(160, 8),
            208 => to_unsigned(162, 8),
            209 => to_unsigned(163, 8),
            210 => to_unsigned(165, 8),
            211 => to_unsigned(167, 8),
            212 => to_unsigned(169, 8),
            213 => to_unsigned(170, 8),
            214 => to_unsigned(172, 8),
            215 => to_unsigned(174, 8),
            216 => to_unsigned(176, 8),
            217 => to_unsigned(178, 8),
            218 => to_unsigned(179, 8),
            219 => to_unsigned(181, 8),
            220 => to_unsigned(183, 8),
            221 => to_unsigned(185, 8),
            222 => to_unsigned(187, 8),
            223 => to_unsigned(189, 8),
            224 => to_unsigned(191, 8),
            225 => to_unsigned(193, 8),
            226 => to_unsigned(194, 8),
            227 => to_unsigned(196, 8),
            228 => to_unsigned(198, 8),
            229 => to_unsigned(200, 8),
            230 => to_unsigned(202, 8),
            231 => to_unsigned(204, 8),
            232 => to_unsigned(206, 8),
            233 => to_unsigned(208, 8),
            234 => to_unsigned(210, 8),
            235 => to_unsigned(212, 8),
            236 => to_unsigned(214, 8),
            237 => to_unsigned(216, 8),
            238 => to_unsigned(218, 8),
            239 => to_unsigned(220, 8),
            240 => to_unsigned(222, 8),
            241 => to_unsigned(224, 8),
            242 => to_unsigned(227, 8),
            243 => to_unsigned(229, 8),
            244 => to_unsigned(231, 8),
            245 => to_unsigned(233, 8),
            246 => to_unsigned(235, 8),
            247 => to_unsigned(237, 8),
            248 => to_unsigned(239, 8),
            249 => to_unsigned(241, 8),
            250 => to_unsigned(244, 8),
            251 => to_unsigned(246, 8),
            252 => to_unsigned(248, 8),
            253 => to_unsigned(250, 8),
            254 => to_unsigned(252, 8),
            255 => to_unsigned(255, 8)
            );
    begin
        
        -- Default register next-state assignments
        next_col_count <= col_count;
        next_bpp_count <= bpp_count;
        next_dly_timer <= dly_timer;
        next_led_addr <= s_led_addr;
        next_rgbUU <= s_rgbUU;
        next_rgbUL <= s_rgbUL;
        next_rgbLU <= s_rgbLU;
        next_rgbLL <= s_rgbLL;
        
        -- Default signal assignments
        s_clk_out <= '0';
        s_lat <= '0';
        s_oe <= '1'; -- this signal is "active low

            
        -- States
        case state is
        
            when INIT =>
                if(dly_timer = 0)then
                    if(sel1 = '1')then
                        case bpp_count is
                            when "000" => next_dly_timer <= to_unsigned(64, next_dly_timer'length);
                            when "001" => next_dly_timer <= to_unsigned(128, next_dly_timer'length);
                            when "010" => next_dly_timer <= to_unsigned(256, next_dly_timer'length);
                            when "011" => next_dly_timer <= to_unsigned(512, next_dly_timer'length);
                            when "100" => next_dly_timer <= to_unsigned(1024, next_dly_timer'length);
                            when "101" => next_dly_timer <= to_unsigned(2048, next_dly_timer'length);
                            when "110" => next_dly_timer <= to_unsigned(4096, next_dly_timer'length);
                            when "111" => next_dly_timer <= to_unsigned(8192, next_dly_timer'length);
                        end case;
                    else
                        case bpp_count is
                            when "000" => next_dly_timer <= to_unsigned(2, next_dly_timer'length);
                            when "001" => next_dly_timer <= to_unsigned(4, next_dly_timer'length);
                            when "010" => next_dly_timer <= to_unsigned(8, next_dly_timer'length);
                            when "011" => next_dly_timer <= to_unsigned(16, next_dly_timer'length);
                            when "100" => next_dly_timer <= to_unsigned(32, next_dly_timer'length);
                            when "101" => next_dly_timer <= to_unsigned(64, next_dly_timer'length);
                            when "110" => next_dly_timer <= to_unsigned(128, next_dly_timer'length);
                            when "111" => next_dly_timer <= to_unsigned(256, next_dly_timer'length);
                        end case;
                    end if;
                    if(s_led_addr = "1111") then
                        next_bpp_count <= bpp_count + 1;
                    end if;
                    next_state <= READ_PIXEL_DATA;
                else
                    next_dly_timer <= dly_timer - 1;
                    next_state <= INIT;
                end if;
                
            when READ_PIXEL_DATA =>
                if(dly_timer /= 0)then
                    s_oe <= '0'; -- enable display
                    next_dly_timer <= dly_timer - 1;
                end if;

                if(sel0 = '0')then
                    UU_r := gamma_table(to_integer(unsigned(dataUU(23 downto 16))));
                    UU_g := gamma_table(to_integer(unsigned(dataUU(15 downto 8))));
                    UU_b := gamma_table(to_integer(unsigned(dataUU(7 downto 0))));
                    UL_r := gamma_table(to_integer(unsigned(dataUL(23 downto 16))));
                    UL_g := gamma_table(to_integer(unsigned(dataUL(15 downto 8))));
                    UL_b := gamma_table(to_integer(unsigned(dataUL(7 downto 0))));
                    LU_r := gamma_table(to_integer(unsigned(dataLU(23 downto 16))));
                    LU_g := gamma_table(to_integer(unsigned(dataLU(15 downto 8))));
                    LU_b := gamma_table(to_integer(unsigned(dataLU(7 downto 0))));
                    LL_r := gamma_table(to_integer(unsigned(dataLL(23 downto 16))));
                    LL_g := gamma_table(to_integer(unsigned(dataLL(15 downto 8))));
                    LL_b := gamma_table(to_integer(unsigned(dataLL(7 downto 0))));
                else
                    UU_r := unsigned(dataUU(23 downto 16));
                    UU_g := unsigned(dataUU(15 downto 8));
                    UU_b := unsigned(dataUU(7 downto 0));
                    UL_r := unsigned(dataUL(23 downto 16));
                    UL_g := unsigned(dataUL(15 downto 8));
                    UL_b := unsigned(dataUL(7 downto 0));
                    LU_r := unsigned(dataLU(23 downto 16));
                    LU_g := unsigned(dataLU(15 downto 8));
                    LU_b := unsigned(dataLU(7 downto 0));
                    LL_r := unsigned(dataLL(23 downto 16));
                    LL_g := unsigned(dataLL(15 downto 8));
                    LL_b := unsigned(dataLL(7 downto 0));
                end if;            

                next_rgbUU <= UU_r(to_integer(bpp_count)) & UU_g(to_integer(bpp_count)) & UU_b(to_integer(bpp_count));
                next_rgbUL <= UL_r(to_integer(bpp_count)) & UL_g(to_integer(bpp_count)) & UL_b(to_integer(bpp_count));
                next_rgbLU <= LU_r(to_integer(bpp_count)) & LU_g(to_integer(bpp_count)) & LU_b(to_integer(bpp_count));
                next_rgbLL <= LL_r(to_integer(bpp_count)) & LL_g(to_integer(bpp_count)) & LL_b(to_integer(bpp_count));

                if(col_count /= "11111110") then -- check if at the rightmost side of the image
                    next_state <= INCR_RAM_ADDR;  -- next row
                else
                    if(dly_timer = 0)then
                        next_dly_timer <= to_unsigned(2,next_dly_timer'length);   --WAIT UNTIL LED ADDRESS LINE UPDATE
                        next_state <= INCR_LED_ADDR;  -- next line
                    else
                        next_state <= READ_PIXEL_DATA;
                    end if;
                end if;

            when INCR_RAM_ADDR =>
                s_clk_out <= '1'; -- pulse the output clock
                if(dly_timer /= 0)then
                    s_oe <= '0'; -- enable display
                    next_dly_timer <= dly_timer - 1;
                end if;
                next_col_count <= col_count - 1;  -- update/increment column counter
                next_state <= READ_PIXEL_DATA;

            when INCR_LED_ADDR =>
                -- display is disabled during led_addr (select lines) update
                if(dly_timer = 0)then
                    next_led_addr <= std_logic_vector(unsigned(s_led_addr) + 1);
                    next_col_count <= to_unsigned(192, next_col_count'length); -- reset the column counter
                    next_dly_timer <= to_unsigned(2, next_dly_timer'length);  --WAIT AFTER LED ADDRESS LINE UPDATE
                    next_state <= LWAIT;
                else
                    next_state <= INCR_LED_ADDR;
                    next_dly_timer <= dly_timer - 1;
                end if;

            when LWAIT =>
                -- display is disabled after led_addr (select lines) update
                if(dly_timer = 0)then
                    next_dly_timer <= to_unsigned(1, next_dly_timer'length);--WAIT DURING LATCH
                    next_state <= LATCH; -- restart state machine
                else
                    next_state <= LWAIT;
                    next_dly_timer <= dly_timer - 1;
                end if;

            when LATCH =>
                -- display is disabled during latchin
                s_lat <= '1'; -- latch the data
                if(dly_timer = 0)then
                    next_dly_timer <= to_unsigned(2, next_dly_timer'length); --WAIT UNTIL SCREEN ENABLE
                    next_state <= INIT; -- restart state machine
                else
                    next_state <= LATCH;
                    next_dly_timer <= dly_timer - 1;
                end if;
            when others => null;
        end case;
    end process;
    
end bhv;