#ifndef LCD_HAL_H
#define LCD_HAL_H

void lcd_init(void);
void lcd_clear(void);
void lcd_write_line(int line, const char *text);
void lcd_write_lines(const char *line1, const char *line2);
void lcd_get_line(int line, char *text_out);
void lcd_get_lines(char *line1_out, char *line2_out);

#endif
