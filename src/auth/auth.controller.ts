import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseIntPipe,
  Post,
  Put,
} from '@nestjs/common';
import { AuthService } from './auth.service';
import { LoginDto } from './dto/login.dto';
import { CreateAdminDto } from './dto/create-admin.dto';
import { UpdateAdminDto } from './dto/update-admin.dto';

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  // 🔐 LOGIN (FRONT)
  @Post('login')
  login(@Body() dto: LoginDto) {
    return this.authService.login(dto.email, dto.password);
  }

  // ➕ CREATE ADMIN (POSTMAN)
  @Post('admins')
  createAdmin(@Body() dto: CreateAdminDto) {
    return this.authService.createAdmin(dto);
  }

  // 📄 LIST ADMINS
  @Get('admins')
  findAllAdmins() {
    return this.authService.findAllAdmins();
  }

  // 🔍 GET ADMIN
  @Get('admins/:id')
  findAdmin(@Param('id', ParseIntPipe) id: number) {
    return this.authService.findAdminById(id);
  }

  // ✏️ UPDATE ADMIN
  @Put('admins/:id')
  updateAdmin(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateAdminDto,
  ) {
    return this.authService.updateAdmin(id, dto);
  }

  // 🗑 DELETE ADMIN
  @Delete('admins/:id')
  deleteAdmin(@Param('id', ParseIntPipe) id: number) {
    return this.authService.deleteAdmin(id);
  }
}
