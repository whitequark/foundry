# Target configuration

#core   := cortex-m3
#series := stm32f1
#device := maple_leaf

core   := cortex-m3
series := stm32l1
device := foundry_gamepad

### DO NOT MODIFY BELOW THIS LINE ###

llvm   :=
cross  := arm-linux-gnueabi-
root   := ..

stdrtl := class.fy object.fy value.fy integer.fy fixed.fy \
	  array.fy symbol.fy lambda.fy
stdrtl := $(addprefix ../rtl/,$(stdrtl))

devrtl := metal/register.fy metal/unit.fy

ifeq ($(series),stm32f1)
devrtl := $(devrtl) $(addprefix $(series)/,rcc.fy afio.fy gpio.fy exti.fy usb.fy $(series).fy)
endif

ifeq ($(series),stm32l1)
devrtl := $(devrtl) $(addprefix $(series)/,rcc.fy pwr.fy gpio.fy $(series).fy)
endif

ifeq ($(device),maple_leaf)
devrtl := $(devrtl) $(addprefix $(device)/,color_lcd_shield.fy $(device).fy)
endif

ifeq ($(device),foundry_gamepad)
devrtl := $(devrtl) $(addprefix $(device)/,gamepad_lcd.fy gamepad.fy)
endif

devrtl := $(addprefix ../rtl/,$(devrtl))

devlib := startup32.ll $(core).ll $(series).ll
devlib := $(addprefix ../lib/startup/,$(devlib))

.SUFFIXES:

# Common rules for all targets

%.fir: $(stdrtl) $(devrtl) %.fy
	$(root)/foundry_vm.native $^ -o $@

%.opt.fir: %.fir
	$(root)/foundry_xfrm.native $^ -std-xfrms -o $@

%.ll: %.bc
	llvm-dis$(llvm) $^ -o $@

%.o: %.opt.bc
	llc$(llvm) -filetype=obj $^ -o $@

%.s: %.opt.bc
	llc$(llvm) -filetype=asm $^ -o $@

%.bin: %.elf
	$(cross)objcopy -Obinary $^ $@

%.ihex: %.elf
	$(cross)objcopy -Oihex $^ $@

clean:
	rm -f *.fir *.bc *.ll *.s *.o *.bin *.elf *.ihex

# (h)ost rules

%.h.bc: %.opt.fir
	$(root)/foundry_gen.native -target x86_64 $^ -o $@

%.h.opt.bc: %.h.bc
	opt$(llvm) $^ \
		-std-link-opts \
		-o $@

%.h.elf: %.h.o
	gcc $^ -o $@

# (d)evice rules

%.d.bc: %.opt.fir
	$(root)/foundry_gen.native -target thumbv7m $^ -o $@

%.d.opt.bc: $(devlib) %.d.bc
	llvm-link$(llvm) $^ | opt$(llvm) \
		-internalize-public-api-list=_startup,__vectors__ \
		-internalize \
		-Os \
		-globaldce \
		-o $@

%.d.elf: %.d.o
	$(cross)ld -L../lib -Tdevices/$(device).ld $^ -o $@

